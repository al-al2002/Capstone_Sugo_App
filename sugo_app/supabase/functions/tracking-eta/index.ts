/**
 * Samples the ETA for one tracking leg, on behalf of the technician driving it.
 *
 * ```
 * POST /functions/v1/tracking-eta
 * { "job_id": "uuid" }
 * ```
 *
 * The calculation itself lives in `_shared/eta_sampler.ts`, shared with
 * `tracking-eta-sweep`. This file is the authorisation half: it decides WHO may
 * ask, and nothing else.
 *
 * ## Why the technician's app calls this, not the client's
 *
 * Detection has to work when the client is not looking - that is the entire
 * feature. The technician's phone is the one that is definitely awake: it is
 * already streaming GPS into `job_tracking`. So the travelling device drives
 * the sampling, and the client's screen just reads the result over Realtime.
 *
 * Letting the client call it would also put the TomTom quota in the hands of
 * whoever opens a screen, rather than the one device with a reason to spend it.
 *
 * ## The one exception: the client's own trip
 *
 * At `ready_for_collection` it is the CLIENT who travels, to collect the unit
 * (20260929000001), so their phone is the awake one and they may sample. On
 * every other stage the rule above stands.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, readJson, serviceClient } from "../_shared/supabase.ts";
import {
  CLIENT_TRIP_STAGE,
  type LegJobRow,
  sampleLegEta,
} from "../_shared/eta_sampler.ts";

interface EtaRequest {
  job_id?: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const body = await readJson<EtaRequest>(req);
    const jobId = body.job_id;
    if (!jobId) return fail("job_id is required", 422);

    const db = serviceClient();

    const { data: job, error: jobError } = await db
      .from("jobs")
      .select("id, client_id, assigned_technician_id, latitude, longitude")
      .eq("id", jobId)
      .maybeSingle<LegJobRow>();

    if (jobError) return fail("Could not load the job", 500, jobError.message);
    if (!job) return fail("Job not found", 404);

    // Only whoever is actually making the trip may sample it: the technician,
    // or the client on the one leg that is theirs.
    if (job.assigned_technician_id !== uid) {
      if (job.client_id !== uid) {
        return fail("Only the assigned technician can update the ETA", 403);
      }
      const { data: leg } = await db
        .from("job_tracking")
        .select("stage")
        .eq("job_id", jobId)
        .maybeSingle<{ stage: string }>();
      if (leg?.stage !== CLIENT_TRIP_STAGE) {
        return fail("Only the assigned technician can update the ETA", 403);
      }
    }

    return json(await sampleLegEta(db, job));
  } catch (error) {
    return fail("Could not update the ETA", 500, (error as Error).message);
  }
});
