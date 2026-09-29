/**
 * Conditions at the destination of a tracking leg.
 *
 * ```
 * POST /functions/v1/job-weather
 * { "job_id": "uuid" }
 * ```
 *
 * ## Why this is a function and not a call from the app
 *
 * `OPENWEATHER_API_KEY` is a Supabase secret. Calling OpenWeatherMap from
 * Flutter would mean shipping that key inside the APK, where anyone can pull it
 * out and spend the quota. Going through here keeps the key on the server, and
 * the device only ever sees the answer.
 *
 * That is also the difference between this and a traffic tile overlay: raster
 * tiles are fetched by the device, so a traffic layer cannot hide its key the
 * way this can.
 *
 * ## Why the destination is resolved here
 *
 * The caller sends a job id and nothing else. Which coordinate matters depends
 * on the leg - the technician heading over and `out_for_delivery` end at the
 * client's address, the rest of the inbound leg at the workshop (see
 * `_shared/leg_destination.ts`) - and that decision reads `job_tracking.stage`, `jobs` and
 * `technicians`. Doing it here means the app cannot ask for the weather at a
 * coordinate of its choosing, which would turn this into a free geocoded
 * weather proxy for anybody with an anon key.
 *
 * ## Cost
 *
 * One call per request, and the app calls it once per leg - not once per GPS
 * fix. Tracking emits a position every few seconds; wiring weather to that
 * stream would multiply usage by roughly three orders of magnitude over a
 * half-hour delivery and exhaust the free tier in a day. The client refetches
 * only when the leg flips.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, readJson, serviceClient } from "../_shared/supabase.ts";
// Single-sourced with the matcher: the severity mapping that decides whether
// Stage 2 discounts a technician is the same one that labels this chip, so the
// two can never disagree about what counts as bad weather.
import { fetchWeather } from "../match-technician/clients/openweather.ts";
// Shared with `tracking-eta`: the ETA must count down to the same place this
// reports the weather for, or the chip describes somewhere else entirely.
import { resolveLegDestination } from "../_shared/leg_destination.ts";

interface WeatherRequest {
  job_id?: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const body = await readJson<WeatherRequest>(req);
    const jobId = body.job_id;
    if (!jobId) return fail("job_id is required", 422);

    const db = serviceClient();

    const { data: job, error: jobError } = await db
      .from("jobs")
      .select("id, client_id, assigned_technician_id, latitude, longitude")
      .eq("id", jobId)
      .maybeSingle<{
        id: string;
        client_id: string;
        assigned_technician_id: string | null;
        latitude: number | null;
        longitude: number | null;
      }>();

    if (jobError) return fail("Could not load the job", 500, jobError.message);
    if (!job) return fail("Job not found", 404);

    // This function runs on the service role, so RLS is not consulted. Only the
    // two people actually on this delivery may ask about it.
    if (job.client_id !== uid && job.assigned_technician_id !== uid) {
      return fail("This job belongs to someone else", 403);
    }

    const destination = await resolveLegDestination(db, job);

    // No tracking row means no transport leg, so there is no destination whose
    // weather would mean anything.
    if (destination.stage === null) {
      return json({ available: false, reason: "no_tracking_leg" });
    }
    if (destination.latitude === null || destination.longitude === null) {
      return json({ available: false, reason: "no_destination" });
    }

    const { latitude, longitude } = destination;
    const destinationLabel = destination.label;
    const outbound = destination.outbound;

    const weather = await fetchWeather(latitude, longitude);

    if (!weather.available) {
      // Deliberately a 200. The chip is supplementary - a failed forecast must
      // not surface as an error on a screen whose job is showing a moving van.
      return json({ available: false, reason: "provider_unavailable" });
    }

    return json({
      available: true,
      condition: weather.condition,
      description: weather.description,
      temp_c: weather.tempC,
      // 0..1, the same figure Stage 2 uses to discount a technician's
      // likelihood of accepting. Sent so the chip can colour itself by how bad
      // the conditions are rather than re-deriving a rule of its own.
      severity: weather.severity,
      label: weather.label,
      destination_label: destinationLabel,
      outbound,
    });
  } catch (error) {
    return fail("Could not load conditions", 500, (error as Error).message);
  }
});
