/**
 * Nightly feedback-loop batch (Step 8).
 *
 * ```
 * POST /functions/v1/aggregate-outcomes      (service-role auth, from pg_cron)
 * -> { technicians, combos, updated, report: [...] }
 * ```
 *
 * Two jobs, one pass over `job_outcomes`.
 *
 * **1. Repair the denormalised counters.** `technicians.rating` and
 * `technicians.total_jobs` are caches of what `job_outcomes` already knows.
 * `job-response` updates them as each job closes, but a crashed request or a
 * row inserted by hand leaves them stale. Recomputing nightly from the source
 * of truth makes drift self-healing rather than permanent.
 *
 * **2. Report the per-combo accuracy signal.** For every technician x device
 * type x problem symptom, this computes the same smoothed accuracy that Stage 1
 * uses, and returns it.
 *
 * ## Why the per-combo signal is reported, not stored
 *
 * The RB-CARS schema is fixed at four tables, with nowhere to cache a
 * per-combo score. Stage 1 therefore computes it live, in one indexed query
 * against `job_outcomes` filtered to the candidate pool - see
 * `match-technician/scoring/accuracy.ts`. That has a real advantage over a
 * cached column: an outcome recorded ten minutes ago already influences the
 * next match, instead of waiting for the next nightly run.
 *
 * This function is the audit view of that same computation. It is what you open
 * to answer "is the feedback loop actually doing anything?" - it shows, per
 * technician and per combo, how the observed accuracy differs from the 0.70
 * prior everyone starts at. If the capstone later needs the cache, the report
 * below is already the exact row shape a `technician_accuracy` table would
 * take.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import {
  isServiceRequest,
  readJson,
  serviceClient,
} from "../_shared/supabase.ts";
import {
  ACCURACY_PRIOR,
  ACCURACY_PRIOR_WEIGHT,
  REROUTE_PENALTY,
} from "../match-technician/scoring/constants.ts";

interface OutcomeRow {
  technician_id: string;
  diagnosis_correct: boolean | null;
  rerouted_mid_job: boolean | null;
  final_rating: number | null;
  jobs: {
    device_type: string;
    problem_symptom: string;
  } | null;
}

interface ComboReport {
  technician_id: string;
  device_type: string;
  problem_symptom: string;
  samples: number;
  correct: number;
  reroutes: number;
  raw_accuracy: number | null;
  smoothed_accuracy: number;
  adjusted_signal: number;
  /** How far the evidence has moved this combo off the shared prior. */
  delta_vs_prior: number;
}

interface TechnicianReport {
  technician_id: string;
  total_outcomes: number;
  rated_outcomes: number;
  average_rating: number;
  overall_signal: number;
  combos: ComboReport[];
}

const round = (value: number, places = 4): number => {
  const factor = 10 ** places;
  return Math.round(value * factor) / factor;
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  // No human caller. This runs from pg_cron with the service role key, or from
  // an operator's curl during a demo. Anything else is refused outright -
  // there is no per-user path into a whole-table recomputation.
  if (!isServiceRequest(req)) {
    return fail("Service role required", 403);
  }

  try {
    const body = await readJson<{ dry_run?: boolean }>(req);
    const dryRun = body.dry_run === true;

    const db = serviceClient();

    const { data: outcomes, error } = await db
      .from("job_outcomes")
      .select(
        "technician_id, diagnosis_correct, rerouted_mid_job, final_rating, " +
          "jobs!inner(device_type, problem_symptom)",
      )
      .returns<OutcomeRow[]>();

    if (error) return fail("Could not read outcomes", 500, error.message);

    const rows = outcomes ?? [];

    if (rows.length === 0) {
      return json({
        technicians: 0,
        combos: 0,
        updated: 0,
        report: [],
        message: "No outcomes recorded yet.",
      });
    }

    // ------------------------------------------------- group by technician
    const byTechnician = new Map<string, OutcomeRow[]>();
    for (const row of rows) {
      const list = byTechnician.get(row.technician_id);
      if (list) list.push(row);
      else byTechnician.set(row.technician_id, [row]);
    }

    const report: TechnicianReport[] = [];
    let updated = 0;
    let comboCount = 0;

    for (const [technicianId, group] of byTechnician) {
      // ---------------------------------------- per device+symptom breakdown
      const byCombo = new Map<string, OutcomeRow[]>();
      for (const row of group) {
        if (!row.jobs) continue;
        const key = `${row.jobs.device_type}::${row.jobs.problem_symptom}`;
        const list = byCombo.get(key);
        if (list) list.push(row);
        else byCombo.set(key, [row]);
      }

      const combos: ComboReport[] = [];

      for (const [key, comboRows] of byCombo) {
        const [deviceType, problemSymptom] = key.split("::");

        const judged = comboRows.filter((row) => row.diagnosis_correct !== null);
        const correct = judged.filter((row) => row.diagnosis_correct).length;
        const reroutes = comboRows.filter((row) => row.rerouted_mid_job).length;

        // The identical formula Stage 1 applies, so the audit and the live
        // scorer can never disagree.
        const smoothed =
          (correct + ACCURACY_PRIOR_WEIGHT * ACCURACY_PRIOR) /
          (judged.length + ACCURACY_PRIOR_WEIGHT);

        const rerouteRate = judged.length > 0 ? reroutes / judged.length : 0;
        const adjusted = Math.max(
          0,
          Math.min(1, smoothed * (1 - REROUTE_PENALTY * rerouteRate)),
        );

        combos.push({
          technician_id: technicianId,
          device_type: deviceType,
          problem_symptom: problemSymptom,
          samples: comboRows.length,
          correct,
          reroutes,
          raw_accuracy: judged.length > 0
            ? round(correct / judged.length)
            : null,
          smoothed_accuracy: round(smoothed),
          adjusted_signal: round(adjusted),
          delta_vs_prior: round(adjusted - ACCURACY_PRIOR),
        });
        comboCount += 1;
      }

      combos.sort((a, b) => b.samples - a.samples);

      // ------------------------------------------- refresh the cached counters
      const rated = group
        .map((row) => row.final_rating)
        .filter((value): value is number => typeof value === "number");

      const average = rated.length > 0
        ? rated.reduce((sum, value) => sum + value, 0) / rated.length
        : 0;

      const judgedAll = group.filter((row) => row.diagnosis_correct !== null);
      const correctAll = judgedAll.filter((row) => row.diagnosis_correct).length;
      const overallSignal =
        (correctAll + ACCURACY_PRIOR_WEIGHT * ACCURACY_PRIOR) /
        (judgedAll.length + ACCURACY_PRIOR_WEIGHT);

      if (!dryRun) {
        const { error: updateError } = await db
          .from("technicians")
          .update({
            total_jobs: group.length,
            rating: round(average, 2),
          })
          .eq("id", technicianId);

        if (updateError) {
          console.warn(
            `could not update technician ${technicianId}:`,
            updateError.message,
          );
        } else {
          updated += 1;
        }
      }

      report.push({
        technician_id: technicianId,
        total_outcomes: group.length,
        rated_outcomes: rated.length,
        average_rating: round(average, 2),
        overall_signal: round(overallSignal),
        combos,
      });
    }

    report.sort((a, b) => b.total_outcomes - a.total_outcomes);

    console.log(
      `aggregate-outcomes: ${byTechnician.size} technicians, ` +
        `${comboCount} device+symptom combos, ${updated} rows updated` +
        (dryRun ? " (dry run)" : ""),
    );

    return json({
      technicians: byTechnician.size,
      combos: comboCount,
      updated,
      dry_run: dryRun,
      prior: ACCURACY_PRIOR,
      report,
    });
  } catch (error) {
    return fail("Aggregation failed", 500, (error as Error).message);
  }
});
