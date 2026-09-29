/**
 * The feedback loop, read side.
 *
 * `job_outcomes` records what actually happened after a job: was the diagnosis
 * right, did it have to be rerouted mid-job, what did the client rate it. This
 * module turns those rows into the `diagnosis_accuracy` factor that Stage 1
 * consumes, so the system's own history changes who it recommends next.
 *
 * Two ideas do the work.
 *
 * **Relevance weighting.** An outcome on the *same device and same symptom* is
 * the strongest evidence. An outcome on the same device but a different symptom
 * still says something, so it counts at `SAME_DEVICE_ONLY_WEIGHT`. Anything
 * else is ignored: being good at laptops says nothing about aircon.
 *
 * **Shrinkage toward a prior.** Raw `correct / total` is meaningless at n = 1,
 * where one lucky job reads as a perfect record. Instead every technician
 * starts at `ACCURACY_PRIOR` and moves toward their observed rate as evidence
 * accumulates:
 *
 * ```
 *            correct + PRIOR_WEIGHT * PRIOR
 * signal =  --------------------------------
 *             total  + PRIOR_WEIGHT
 * ```
 *
 * With `PRIOR_WEIGHT = 3` it takes roughly three relevant jobs before a
 * technician's own record outweighs the prior. That is what keeps a newcomer
 * from being buried and a one-job wonder from topping the list.
 */
import {
  ACCURACY_PRIOR,
  ACCURACY_PRIOR_WEIGHT,
  REROUTE_PENALTY,
  SAME_DEVICE_ONLY_WEIGHT,
} from "./constants.ts";
import { clamp01 } from "./geo.ts";
import { round } from "./weighting.ts";
import type { AccuracyStats, JobRow } from "./types.ts";

/** A `job_outcomes` row joined to the `jobs` row it describes. */
export interface OutcomeRow {
  technician_id: string;
  diagnosis_correct: boolean | null;
  rerouted_mid_job: boolean | null;
  final_rating: number | null;
  jobs: {
    device_type: string;
    problem_symptom: string;
  } | null;
}

/** What a technician with no relevant history scores: unknown, not bad. */
export function defaultAccuracy(): AccuracyStats {
  return {
    similarRepairs: 0,
    sameDeviceRepairs: 0,
    signal: ACCURACY_PRIOR,
    rerouteRate: 0,
    averageRating: null,
  };
}

/**
 * Groups outcome rows by technician and reduces each group to an
 * `AccuracyStats`. Technicians with no rows simply never appear in the map;
 * callers fall back to `defaultAccuracy()`.
 */
export function buildAccuracyIndex(
  rows: OutcomeRow[],
  job: JobRow,
): Map<string, AccuracyStats> {
  const grouped = new Map<string, OutcomeRow[]>();

  for (const row of rows) {
    const list = grouped.get(row.technician_id);
    if (list) list.push(row);
    else grouped.set(row.technician_id, [row]);
  }

  const index = new Map<string, AccuracyStats>();
  for (const [technicianId, group] of grouped) {
    index.set(technicianId, reduceOutcomes(group, job));
  }
  return index;
}

function reduceOutcomes(rows: OutcomeRow[], job: JobRow): AccuracyStats {
  let weightedTotal = 0;
  let weightedCorrect = 0;
  let weightedReroutes = 0;
  let similarRepairs = 0;
  let sameDeviceRepairs = 0;
  let ratingSum = 0;
  let ratingCount = 0;

  for (const row of rows) {
    const context = row.jobs;
    if (!context) continue;
    if (context.device_type !== job.device_type) continue;

    const exact = context.problem_symptom === job.problem_symptom;
    const weight = exact ? 1 : SAME_DEVICE_ONLY_WEIGHT;

    sameDeviceRepairs += 1;
    if (exact) similarRepairs += 1;

    // A null diagnosis_correct means the outcome was logged without a verdict.
    // It still counts toward volume but not toward correctness either way.
    if (row.diagnosis_correct !== null) {
      weightedTotal += weight;
      if (row.diagnosis_correct) weightedCorrect += weight;
      if (row.rerouted_mid_job) weightedReroutes += weight;
    }

    if (typeof row.final_rating === "number") {
      ratingSum += row.final_rating;
      ratingCount += 1;
    }
  }

  const smoothed =
    (weightedCorrect + ACCURACY_PRIOR_WEIGHT * ACCURACY_PRIOR) /
    (weightedTotal + ACCURACY_PRIOR_WEIGHT);

  const rerouteRate = weightedTotal > 0 ? weightedReroutes / weightedTotal : 0;

  // A technician who keeps having to reroute mid-job was reading the symptom
  // wrong even when the eventual repair succeeded, so discount the signal.
  const signal = clamp01(smoothed * (1 - REROUTE_PENALTY * rerouteRate));

  return {
    similarRepairs,
    sameDeviceRepairs,
    signal: round(signal),
    rerouteRate: round(rerouteRate),
    averageRating: ratingCount > 0 ? round(ratingSum / ratingCount, 2) : null,
  };
}
