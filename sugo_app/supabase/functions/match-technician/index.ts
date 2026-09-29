/**
 * RB-CARS matching engine - HTTP entry point.
 *
 * ```
 * POST /functions/v1/match-technician
 * { "job_id": "uuid", "exclude_technician_ids": ["uuid", ...] }
 *
 * -> { job_id, evaluated, matches: [ ...job_matches rows... ], context }
 * ```
 *
 * This file does three things and nothing else: authenticate, authorise, then
 * hand off to `scoring/engine.ts`. All the ranking logic lives there so
 * `job-response` can re-run it during a decline cascade without going back out
 * over HTTP.
 *
 * ## The authorisation seam
 *
 * `serviceClient()` ignores RLS, which is the only way to read the whole
 * technician pool. That makes the ownership check below load-bearing: the
 * service role is what *can* be done, `job.client_id === uid` is what *may* be.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, readJson, serviceClient } from "../_shared/supabase.ts";
import { runMatching } from "./scoring/engine.ts";
import type { JobRow } from "./scoring/types.ts";

interface MatchRequest {
  job_id?: string;
  /** Technicians who already declined, so a re-run does not re-offer them. */
  exclude_technician_ids?: string[];
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const body = await readJson<MatchRequest>(req);
    const jobId = body.job_id;
    if (!jobId) return fail("job_id is required", 422);

    const db = serviceClient();

    const { data: job, error: jobError } = await db
      .from("jobs")
      .select("*")
      .eq("id", jobId)
      .maybeSingle<JobRow>();

    if (jobError) return fail("Could not load the job", 500, jobError.message);
    if (!job) return fail("Job not found", 404);

    // Re-impose the rule `jobs_client_select_own` would have applied, now that
    // the service client has bypassed it.
    if (job.client_id !== uid && job.assigned_technician_id !== uid) {
      return fail("This job belongs to someone else", 403);
    }

    const result = await runMatching(
      db,
      job,
      body.exclude_technician_ids ?? [],
    );

    return json({
      job_id: result.jobId,
      evaluated: result.evaluated,
      matches: result.matches,
      considered: result.considered,
      message: result.message,
      context: result.context,
    });
  } catch (error) {
    return fail("Matching failed", 500, (error as Error).message);
  }
});
