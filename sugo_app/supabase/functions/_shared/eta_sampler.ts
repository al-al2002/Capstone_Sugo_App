/**
 * Samples one tracking leg's ETA and decides whether it is running late.
 *
 * Extracted from `tracking-eta` so two callers can share it without either one
 * reimplementing the promise model:
 *
 *   * `tracking-eta`       - the technician's app, while they are driving.
 *   * `tracking-eta-sweep` - pg_cron, for legs whose app has gone quiet.
 *
 * The second is the reason this file exists. Sampling was driven entirely by
 * the position stream, so a technician whose app was killed, backgrounded or
 * simply sitting still in gridlock stopped being measured at exactly the moment
 * they were most likely to be late. The sweep runs the identical calculation
 * from the LAST KNOWN position: they have not moved, time has passed, so the
 * projected arrival slides and the delay grows - which is correct.
 *
 * Callers are responsible for authorising. This module assumes that is done.
 */
import { resolveLegDestination } from "./leg_destination.ts";
import {
  haversineKm,
  travelMinutes,
} from "../match-technician/scoring/geo.ts";
import { fetchTraffic } from "../match-technician/clients/tomtom.ts";
import { fetchWeather } from "../match-technician/clients/openweather.ts";
import { sendPush } from "./fcm.ts";

/**
 * How late counts as late.
 *
 * Ten minutes, chosen against the method rather than plucked: over the ~25 km
 * this app covers, straight-line distance understates road distance by roughly
 * 20-30%, which at city speeds is several minutes of error on its own. A
 * threshold inside that band would fire on the estimate's own noise. Ten
 * minutes is also the point at which a waiting client would notice unaided.
 */
export const DELAY_THRESHOLD_MINUTES = 10;

/** Minimum gap between samples, enforced here rather than trusted to callers. */
export const MIN_SAMPLE_INTERVAL_MS = 90_000;

/**
 * Congestion above this is blamed for a delay. `describe()` in the TomTom
 * client calls anything under 0.15 "clear roads", so 0.35 is comfortably into
 * genuinely slow traffic rather than ordinary city driving.
 */
const TRAFFIC_ATTRIBUTION = 0.35;

/**
 * Weather severity above this is blamed. Matches the app's own
 * `TrackingWeather.adverseThreshold`, which sits between drizzle (0.35) and
 * rain (0.55) in `WEATHER_SEVERITY`, so the chip the client can see and the
 * reason attributed here agree.
 */
const WEATHER_ATTRIBUTION = 0.4;

export interface LegJobRow {
  id: string;
  client_id: string;
  assigned_technician_id: string | null;
  latitude: number | null;
  longitude: number | null;
}

interface TrackingRow {
  stage: string;
  latitude: number | null;
  longitude: number | null;
  expected_arrival_at: string | null;
  eta_sampled_at: string | null;
  delay_notified_at: string | null;
}

// deno-lint-ignore no-explicit-any
type Db = any;

/** Samples one leg. Never throws; every failure is a `sampled: false` reason. */
export async function sampleLegEta(
  db: Db,
  job: LegJobRow,
): Promise<Record<string, unknown>> {
  const jobId = job.id;

  const { data: tracking } = await db
    .from("job_tracking")
    .select(
      "stage, latitude, longitude, expected_arrival_at, eta_sampled_at, " +
        "delay_notified_at",
    )
    .eq("job_id", jobId)
    .maybeSingle<TrackingRow>();

  if (!tracking) return ({ sampled: false, reason: "no_tracking_leg" });

  // No fix yet, so there is nothing to measure from.
  if (tracking.latitude === null || tracking.longitude === null) {
    return ({ sampled: false, reason: "no_position" });
  }

  // The server-side throttle. Returning 200 rather than 429: an over-eager
  // caller is not an error condition, it just gets told no work was done.
  const lastSample = tracking.eta_sampled_at
    ? Date.parse(tracking.eta_sampled_at)
    : null;
  if (
    lastSample !== null &&
    Date.now() - lastSample < MIN_SAMPLE_INTERVAL_MS
  ) {
    return ({ sampled: false, reason: "throttled" });
  }

  const destination = await resolveLegDestination(db, job);
  if (destination.latitude === null || destination.longitude === null) {
    return ({ sampled: false, reason: "no_destination" });
  }

  const distanceKm = haversineKm(
    tracking.latitude,
    tracking.longitude,
    destination.latitude,
    destination.longitude,
  );

  // Both sampled at the destination, matching where `job-weather` reports
  // from, and run together so one slow provider does not double the latency.
  const [traffic, weather] = await Promise.all([
    fetchTraffic(destination.latitude, destination.longitude),
    fetchWeather(destination.latitude, destination.longitude),
  ]);

  const etaMinutes = travelMinutes(distanceKm, traffic.currentSpeed);
  if (etaMinutes === null) {
    return ({ sampled: false, reason: "no_estimate" });
  }

  const now = Date.now();
  const projectedArrival = new Date(now + etaMinutes * 60_000);

  // First sample of this leg: today's estimate becomes the promise. The
  // stage-change trigger clears it, so a new leg lands here again.
  const expectedArrival = tracking.expected_arrival_at
    ? new Date(Date.parse(tracking.expected_arrival_at))
    : projectedArrival;

  const delayMinutes =
    (projectedArrival.getTime() - expectedArrival.getTime()) / 60_000;

  const isLate = delayMinutes >= DELAY_THRESHOLD_MINUTES;

  // Only claimed when the sampled data actually supports it. A delay with no
  // bad traffic and no bad weather gets no reason rather than a guessed one -
  // the technician may simply be running behind, and saying "traffic" would
  // be inventing an excuse on their behalf.
  let reason: string | null = null;
  if (isLate) {
    const badTraffic = traffic.available &&
      ((traffic.congestion ?? 0) >= TRAFFIC_ATTRIBUTION || traffic.roadClosure);
    const badWeather = weather.available &&
      (weather.severity ?? 0) >= WEATHER_ATTRIBUTION;

    if (badTraffic && badWeather) reason = "both";
    else if (badTraffic) reason = "traffic";
    else if (badWeather) reason = "weather";
  }

  // Announce once per leg, not on every sample for the rest of the journey.
  const shouldNotify = isLate && tracking.delay_notified_at === null;

  let pushed = 0;
  if (shouldNotify) {
    pushed = await notifyClient(db, job.client_id, {
      delayMinutes,
      reason,
      destinationLabel: destination.label,
    });
  }

  const { error: writeError } = await db
    .from("job_tracking")
    .update({
      expected_arrival_at: expectedArrival.toISOString(),
      projected_arrival_at: projectedArrival.toISOString(),
      delay_minutes: Number(delayMinutes.toFixed(1)),
      delay_reason: reason,
      eta_sampled_at: new Date(now).toISOString(),
      // Stamped whether or not the push actually went out. If FCM is
      // unconfigured or the client has no device registered, the delay is
      // still recorded as announced - the banner carries it over Realtime,
      // and retrying the push on every subsequent sample would spend quota
      // rediscovering the same "nobody to tell".
      ...(shouldNotify
        ? { delay_notified_at: new Date(now).toISOString() }
        : {}),
    })
    .eq("job_id", jobId);

  if (writeError) {
    return { sampled: false, reason: "write_failed" };
  }

  return ({
    sampled: true,
    eta_minutes: Number(etaMinutes.toFixed(1)),
    distance_km: Number(distanceKm.toFixed(2)),
    expected_arrival_at: expectedArrival.toISOString(),
    projected_arrival_at: projectedArrival.toISOString(),
    delay_minutes: Number(delayMinutes.toFixed(1)),
    delay_reason: reason,
    is_late: isLate,
    notified: shouldNotify,
    pushed,
    destination_label: destination.label,
    traffic_label: traffic.available ? traffic.label : null,
    weather_label: weather.available ? weather.label : null,
  });
}

/**
 * Pushes the delay to the client's devices.
 *
 * Returns how many actually went out. Never throws: the ETA sample is the
 * important write, and a push failure must not roll it back or surface as an
 * error to the technician who triggered it.
 */
async function notifyClient(
  // deno-lint-ignore no-explicit-any
  db: any,
  clientId: string,
  delay: {
    delayMinutes: number;
    reason: string | null;
    destinationLabel: string;
  },
): Promise<number> {
  try {
    const { data: devices } = await db
      .from("device_tokens")
      .select("token")
      .eq("user_id", clientId)
      .returns<{ token: string }[]>();

    const tokens = (devices ?? []).map((row: { token: string }) => row.token);
    if (tokens.length === 0) return 0;

    // Rounded to five minutes, matching `JobTracking.delayLabel` in the app.
    // The estimate is straight-line distance over a sampled speed, so a figure
    // like "17 minutes" would claim a precision the method does not have.
    const rounded = Math.max(5, Math.round(delay.delayMinutes / 5) * 5);

    const cause = delay.reason === "traffic"
      ? " because of heavy traffic"
      : delay.reason === "weather"
      ? " because of bad weather"
      : delay.reason === "both"
      ? " because of traffic and weather"
      : "";

    const result = await sendPush(tokens, {
      title: "Your technician is running late",
      body:
        `About ${rounded} minutes behind${cause}. Tap to see their live position.`,
      data: { type: "job_delay", destination: delay.destinationLabel },
    });

    // FCM said these installs are gone, so the rows are dead weight. Deleting
    // on the reply is what keeps device_tokens self-cleaning.
    if (result.stale.length > 0) {
      await db.from("device_tokens").delete().in("token", result.stale);
    }

    return result.sent;
  } catch (error) {
    console.warn("delay push failed", (error as Error).message);
    return 0;
  }
}
