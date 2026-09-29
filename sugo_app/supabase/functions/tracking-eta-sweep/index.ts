/**
 * Resamples tracking legs whose technician app has gone quiet.
 *
 * ```
 * POST /functions/v1/tracking-eta-sweep
 * header: x-cron-secret: <CRON_SECRET>
 * ```
 *
 * ## The blind spot this closes
 *
 * ETA sampling was driven entirely by the technician's position stream. That
 * works while the app is reporting - and fails in exactly the case the feature
 * exists for. A technician stuck in gridlock is not moving, so `geolocator`
 * sends nothing, so nothing resamples, so the delay is never detected. Same if
 * the app is backgrounded, killed, or the phone loses signal.
 *
 * This sweep runs on a schedule and resamples any leg that has not been looked
 * at recently, using the LAST KNOWN position. That is not a degraded estimate:
 * if they have not moved, the distance still stands, and since time has passed
 * the projected arrival slides while the frozen promise does not. The delay
 * grows on its own, which is the honest answer.
 *
 * ## Why a shared secret and not the service-role key
 *
 * pg_cron has to authenticate somehow. Putting `SUPABASE_SERVICE_ROLE_KEY` in a
 * `cron.job` command would write a key that bypasses every RLS policy into a
 * database table, to buy nothing - this endpoint needs exactly one privilege,
 * which is "may trigger a sweep".
 *
 * So the cron carries `CRON_SECRET`, which grants only that. The worst an
 * attacker who obtains it can do is make the server recompute ETAs it was going
 * to recompute anyway. Compare that to what a leaked service-role key costs.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";
import {
  type LegJobRow,
  MIN_SAMPLE_INTERVAL_MS,
  sampleLegEta,
} from "../_shared/eta_sampler.ts";

/**
 * Stages where something is actually travelling. `in_repair` is at the bench
 * and `delivered` is finished - neither has a journey left to be late for.
 */
const TRAVELLING_STAGES = [
  "heading_to_pickup",
  "collected",
  "returning_to_shop",
  "out_for_delivery",
];

/**
 * How stale a leg must be before the sweep takes it.
 *
 * Four minutes, against the app's own two-minute cadence. That gap matters: set
 * it at or below the app's interval and the sweep would race a perfectly
 * healthy app, doubling TomTom calls on every active delivery to discover
 * nothing. Only a leg that has genuinely missed its own updates is picked up.
 */
const STALE_AFTER_MS = 4 * 60_000;

/**
 * Ceiling per run, so one sweep cannot spend the whole TomTom quota.
 *
 * Legs are taken oldest-first, so anything skipped is simply picked up on the
 * next tick rather than starved.
 */
const MAX_PER_RUN = 20;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const expected = Deno.env.get("CRON_SECRET");
    if (!expected) {
      console.warn("CRON_SECRET is not set; sweep is disabled");
      return fail("Sweep is not configured", 503);
    }
    if (req.headers.get("x-cron-secret") !== expected) {
      return fail("Not authorised", 401);
    }

    const db = serviceClient();
    const cutoff = new Date(Date.now() - STALE_AFTER_MS).toISOString();

    // Legs that are travelling, have a position to measure from, and have not
    // been sampled recently. `eta_sampled_at is null` is included so a leg that
    // has never been sampled - the app died before its first call - still gets
    // picked up.
    const { data: legs, error } = await db
      .from("job_tracking")
      .select("job_id, eta_sampled_at")
      .in("stage", TRAVELLING_STAGES)
      .not("latitude", "is", null)
      .or(`eta_sampled_at.is.null,eta_sampled_at.lt.${cutoff}`)
      .order("eta_sampled_at", { ascending: true, nullsFirst: true })
      .limit(MAX_PER_RUN)
      .returns<{ job_id: string; eta_sampled_at: string | null }[]>();

    if (error) return fail("Could not list legs", 500, error.message);

    const candidates = legs ?? [];
    if (candidates.length === 0) {
      return json({ swept: 0, sampled: 0, skipped: 0 });
    }

    const { data: jobs } = await db
      .from("jobs")
      .select("id, client_id, assigned_technician_id, latitude, longitude")
      .in("id", candidates.map((leg) => leg.job_id))
      .returns<LegJobRow[]>();

    let sampled = 0;
    let skipped = 0;

    // Sequential on purpose. These are all outbound calls to TomTom and
    // OpenWeatherMap, and firing twenty at once is how a free tier starts
    // returning 429s - which would look exactly like "the providers are down"
    // and silently disable delay detection.
    for (const job of jobs ?? []) {
      const result = await sampleLegEta(db, job);
      if (result.sampled === true) sampled += 1;
      else skipped += 1;
    }

    // `MIN_SAMPLE_INTERVAL_MS` is reported so a skew between the cron schedule
    // and the sampler's own throttle shows up in the logs as skips rather than
    // as a silently idle sweep.
    return json({
      swept: candidates.length,
      sampled,
      skipped,
      throttle_ms: MIN_SAMPLE_INTERVAL_MS,
    });
  } catch (error) {
    return fail("Sweep failed", 500, (error as Error).message);
  }
});
