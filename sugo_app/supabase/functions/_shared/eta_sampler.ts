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
 *
 * ## Who is travelling
 *
 * Every leg is the technician's, except the two where the CLIENT comes to the
 * workshop: `ready_for_collection` (collecting it, 20260929000001) and
 * `dropping_off` (bringing it in, 20261117000006). On those legs the position
 * is `client_latitude` / `client_longitude`, the trip only counts between
 * "I'm on my way" and "I've arrived", and a delay is pushed to the TECHNICIAN
 * - the person waiting - instead of the client.
 */
import { resolveLegDestination } from "./leg_destination.ts";
import {
  haversineKm,
  travelMinutes,
} from "../match-technician/scoring/geo.ts";
import { fetchTraffic } from "../match-technician/clients/tomtom.ts";
import { fetchWeather } from "../match-technician/clients/openweather.ts";
import { sendPush } from "./fcm.ts";
import { deviceNoun, firstNameOf, notifyUser } from "./notify.ts";
import { announcesArrival } from "./arrival.ts";

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
  projected_arrival_at: string | null;
  eta_sampled_at: string | null;
  delay_notified_at: string | null;
  client_latitude: number | null;
  client_longitude: number | null;
  client_trip_started_at: string | null;
  client_arrived_at: string | null;
}

/**
 * The legs the client travels: bringing the unit in on a drop-off
 * (20261117000006), and coming back to collect it (20260929000001).
 */
export const CLIENT_TRIP_STAGES: readonly string[] = [
  "dropping_off",
  "ready_for_collection",
];

/** True on a leg where the client, not the technician, is travelling. */
export function isClientTripStage(stage: string | null | undefined): boolean {
  return stage != null && CLIENT_TRIP_STAGES.includes(stage);
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
      "stage, latitude, longitude, expected_arrival_at, projected_arrival_at, " +
        "eta_sampled_at, delay_notified_at, client_latitude, client_longitude, " +
        "client_trip_started_at, client_arrived_at",
    )
    .eq("job_id", jobId)
    .maybeSingle<TrackingRow>();

  if (!tracking) return ({ sampled: false, reason: "no_tracking_leg" });

  // The client's leg exists only between "on my way" and "arrived". Outside
  // that window nobody is travelling towards the shop, so there is nothing to
  // be late for.
  const clientTrip = isClientTripStage(tracking.stage);
  if (
    clientTrip &&
    (tracking.client_trip_started_at === null ||
      tracking.client_arrived_at !== null)
  ) {
    return ({ sampled: false, reason: "client_not_travelling" });
  }

  const originLat = clientTrip ? tracking.client_latitude : tracking.latitude;
  const originLon = clientTrip
    ? tracking.client_longitude
    : tracking.longitude;

  // No fix yet, so there is nothing to measure from.
  if (originLat === null || originLon === null) {
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
    originLat,
    originLon,
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

  // Whoever is WAITING hears about it: the client for the technician's legs,
  // the technician for the client's.
  let pushed = 0;
  if (shouldNotify) {
    pushed = await notifyDelay(
      db,
      clientTrip ? job.assigned_technician_id : job.client_id,
      {
        delayMinutes,
        reason,
        destinationLabel: destination.label,
        clientTrip,
        jobId,
      },
    );
  }

  // "Almost there" (2026-11-17). Stateless, so no column is needed: the
  // previous sample's estimate is still on the row, and an announcement is
  // the crossing - "it was further than three minutes then, it is within
  // them now". Only on legs that end where someone is waiting: the
  // technician heading to the client (to repair, collect or deliver), or the
  // client heading to the shop. Never fatal.
  const previousEta = tracking.projected_arrival_at && tracking.eta_sampled_at
    ? (Date.parse(tracking.projected_arrival_at) -
      Date.parse(tracking.eta_sampled_at)) / 60_000
    : null;
  const endsWithSomeoneWaiting = clientTrip ||
    destination.stage === "heading_to_pickup" ||
    destination.stage === "out_for_delivery";
  const arrivingSoon = announcesArrival({
    previousEtaMinutes: previousEta,
    etaMinutes,
    endsWithSomeoneWaiting,
  });
  if (arrivingSoon) {
    await notifyArriving(db, job, {
      clientTrip,
      stage: destination.stage,
      minutes: Math.max(1, Math.round(etaMinutes)),
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
      // The conditions this sample was taken in (2026-11-17), for the trip
      // card on both sides. Saved from the SAME fetch that decided
      // `delay_reason`, so the card and the delay pop-up always agree.
      traffic_label: traffic.available ? traffic.label : null,
      traffic_congestion: traffic.available ? unitOrNull(traffic.congestion) : null,
      weather_label: weather.available ? weather.label : null,
      weather_severity: weather.available ? unitOrNull(weather.severity) : null,
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
 * "Almost there", to whoever is waiting (2026-11-17). Never throws.
 *
 * The client hears it about their technician (or their repaired unit on its
 * way back); the technician hears it about a client coming to the shop.
 */
async function notifyArriving(
  // deno-lint-ignore no-explicit-any
  db: any,
  job: LegJobRow,
  leg: { clientTrip: boolean; stage: string | null; minutes: number },
): Promise<void> {
  try {
    const away = `About ${leg.minutes} min away.`;
    if (leg.clientTrip) {
      const client = await firstNameOf(db, job.client_id, "Your client");
      await notifyUser(db, job.assigned_technician_id, {
        title: `${client} is almost there`,
        body: leg.stage === "dropping_off"
          ? `${away} They are bringing the unit to your shop.`
          : `${away} They are coming to collect it.`,
        data: { type: "client_arriving", job_id: job.id },
      });
      return;
    }

    const technician = await firstNameOf(
      db,
      job.assigned_technician_id,
      "Your technician",
    );
    const { data: row } = await db
      .from("jobs")
      .select("device_type")
      .eq("id", job.id)
      .maybeSingle();
    const noun = deviceNoun((row as { device_type?: string } | null)?.device_type);
    await notifyUser(db, job.client_id, leg.stage === "out_for_delivery"
      ? {
        title: `Your ${noun} is almost back`,
        body: `${away} ${technician} is bringing it to you.`,
        data: { type: "arriving", job_id: job.id },
      }
      : {
        title: `${technician} is almost there`,
        body: `${away} Get ready to meet them.`,
        data: { type: "arriving", job_id: job.id },
      });
  } catch (error) {
    console.warn("arriving push failed", (error as Error).message);
  }
}

/**
 * A 0..1 reading clamped and rounded for a `numeric(4,3)` column, or null.
 *
 * Guards the ETA write: a NaN from a provider would make PostgREST reject
 * the WHOLE update, and the ETA - the part that matters - would be lost with
 * the labels.
 */
function unitOrNull(value: number | null): number | null {
  if (value === null || !Number.isFinite(value)) return null;
  return Number(Math.min(1, Math.max(0, value)).toFixed(3));
}

/**
 * Pushes the delay to the devices of whoever is waiting.
 *
 * Returns how many actually went out. Never throws: the ETA sample is the
 * important write, and a push failure must not roll it back or surface as an
 * error to the person whose app triggered it.
 */
async function notifyDelay(
  // deno-lint-ignore no-explicit-any
  db: any,
  recipientId: string | null,
  delay: {
    delayMinutes: number;
    reason: string | null;
    destinationLabel: string;
    clientTrip: boolean;
    jobId: string;
  },
): Promise<number> {
  if (!recipientId) return 0;
  try {
    const { data: devices } = await db
      .from("device_tokens")
      .select("token")
      .eq("user_id", recipientId)
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

    const result = await sendPush(
      tokens,
      delay.clientTrip
        ? {
          title: "Your client is running late",
          body:
            `About ${rounded} minutes behind${cause}. Tap to see where they are.`,
          data: { type: "client_delay", job_id: delay.jobId },
        }
        : {
          title: "Your technician is running late",
          body:
            `About ${rounded} minutes behind${cause}. Tap to see their live position.`,
          data: {
            type: "job_delay",
            job_id: delay.jobId,
            destination: delay.destinationLabel,
          },
        },
    );

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
