/**
 * Was this job rerouted to the shop after it was matched? (2026-11-16)
 *
 * `job_outcomes.rerouted_mid_job` used to be a switch the technician set when
 * closing a job. At the user's request the question was removed from the
 * completion sheet - and it never needed asking: the system itself is what
 * moves a job to the shop. Both ways of doing it, "needs the shop" when
 * accepting (`reroute`) and "Take it to your shop" mid-job (`needs_shop`),
 * set `jobs.service_path` to `pickup`.
 *
 * So the answer is a comparison. The technician's `job_matches` row keeps a
 * snapshot of the job as it was matched (`score_breakdown.job`). If the
 * snapshot was not a pickup and the job now is, it was rerouted.
 *
 * Returns null when either side is unknown - an old match with no snapshot -
 * so the caller can fall back rather than guess.
 */
export function wasRerouted(
  snapshotPath: unknown,
  currentPath: unknown,
): boolean | null {
  if (typeof snapshotPath !== "string" || snapshotPath.length === 0) {
    return null;
  }
  if (typeof currentPath !== "string" || currentPath.length === 0) {
    return null;
  }
  return snapshotPath !== "pickup" && currentPath === "pickup";
}

/** `score_breakdown.job.service_path`, or undefined when it is not there. */
export function snapshotServicePath(scoreBreakdown: unknown): unknown {
  if (!scoreBreakdown || typeof scoreBreakdown !== "object") return undefined;
  const job = (scoreBreakdown as Record<string, unknown>).job;
  if (!job || typeof job !== "object") return undefined;
  return (job as Record<string, unknown>).service_path;
}
