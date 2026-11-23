/**
 * The work record's checkpoints, as a technician reads them (2026-11-22).
 *
 * `job_evidence.milestone` is one vocabulary for every kind of job; what the
 * unit-as-found checkpoint is CALLED depends on how the job travels:
 *
 *   home visit  ->  "Before"
 *   pickup      ->  "Collected"
 *   drop-off    ->  "Unit received"
 *
 * The app shows the same names (`EvidenceMilestone.labelFor` in
 * `lib/features/evidence/models/job_evidence.dart`); `evidence.test.ts` pins
 * them so the two cannot drift.
 *
 * Which checkpoints are required, and whether a job is exempt, is decided in
 * SQL by `job_evidence_missing()` (migration 20261122000002). This file only
 * words the refusal.
 */

export type Milestone = "intake" | "diagnosis" | "progress" | "after" | "handover";

export function milestoneLabel(
  milestone: string,
  servicePath: string | null | undefined,
  deliveryOption: string | null | undefined,
): string {
  switch (milestone) {
    case "intake":
      if (servicePath === "home_service") return "Before";
      return deliveryOption === "self" ? "Unit received" : "Collected";
    case "after":
      return servicePath === "home_service" ? "After" : "After repair";
    case "diagnosis":
      return "Diagnosis";
    case "progress":
      return "Progress";
    case "handover":
      return "Handover";
    default:
      return milestone;
  }
}

/**
 * "Add the Before and After photos to the work record before marking this job
 * complete." - the message `job-response` returns when completion is refused.
 */
export function missingEvidenceMessage(
  missing: string[],
  servicePath: string | null | undefined,
  deliveryOption: string | null | undefined,
): string {
  const names = missing.map((m) => milestoneLabel(m, servicePath, deliveryOption));
  const list = names.length <= 1
    ? (names[0] ?? "required")
    : `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
  const noun = names.length === 1 ? "photo" : "photos";
  return `Add the ${list} ${noun} to the work record before marking this job complete.`;
}
