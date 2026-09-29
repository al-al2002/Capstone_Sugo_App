/**
 * Stage 3 - Recommendation.
 *
 * Matching (Stages 1 and 2) answers "who is qualified and compatible?".
 * Recommendation answers a different question: "of those, who is most
 * relevant to THIS client, in THIS situation?". The two stage scores are its
 * biggest inputs, and three things neither stage can see are added:
 *
 * | Factor                   | Asks                                            |
 * |--------------------------|-------------------------------------------------|
 * | `context_fit`            | Do they fit today's conditions?                 |
 * | `client_preference`      | What does this client's own history say?        |
 * | `technician_performance` | Do they answer offers? How much have they done? |
 *
 * The result is the recommendation score. It is what the Top 3 is ranked by,
 * and it is stored as `job_matches.final_score`.
 *
 * ## Cold start, both sides
 *
 * A client with no past bookings has no preferences, so `client_preference`
 * is null and `combine` drops it and shares its weight out - nobody is ranked
 * on a preference the client never showed. A technician with no offers yet
 * sits at `RESPONSE_PRIOR`, not at zero.
 *
 * Pure: no Deno APIs, no network.
 */
import {
  CLIENT_PREFERENCE_SCORE,
  ETA_FIT_MINUTES,
  EXPERIENCE_SATURATION_JOBS,
  MAX_WORKLOAD,
  OUTSIDE_SERVICE_AREA_FIT,
  POORLY_RATED_STARS,
  RECOMMENDATION_WEIGHTS,
  RESPONSE_PRIOR,
  RESPONSE_PRIOR_WEIGHT,
  SOFT_RADIUS_KM,
  WELL_RATED_STARS,
} from "./constants.ts";
import { clamp01 } from "./geo.ts";
import { reweight } from "./rules.ts";
import { combine, type FactorInput, round } from "./weighting.ts";
import type {
  ClientHistory,
  ContextSignal,
  StageResult,
  TrackRecord,
  WeightMultipliers,
} from "./types.ts";

/**
 * How well a technician fits the conditions right now.
 *
 * A mean of whichever components apply - each only when its situation holds:
 *
 * * **service area** - inside the radius they declared, always when known.
 * * **travel time** - minutes at current traffic speed, for on-site visits.
 * * **ready now** - free and not on vacation, when the client needs it today.
 * * **short trip in the rain** - distance again, when it is raining on an
 *   on-site visit. Counted on purpose: rain is when a long ride hurts most.
 *
 * Null when none applies (a remote job that can wait, with no location),
 * which drops the factor rather than scoring anyone zero.
 */
export function contextFitScore(input: {
  signals: ContextSignal[];
  distanceKm: number | null;
  serviceRadiusKm: number | null;
  etaMinutes: number | null;
  onVacation: boolean;
  workload: number;
}): { value: number | null; note: string } {
  const held = new Set(input.signals);
  const parts: number[] = [];
  const notes: string[] = [];

  const radius = input.serviceRadiusKm ?? 0;
  if (input.distanceKm !== null && radius > 0) {
    const inside = input.distanceKm <= radius;
    parts.push(inside ? 1 : OUTSIDE_SERVICE_AREA_FIT);
    notes.push(inside ? "inside their service area" : "outside their service area");
  }

  if (held.has("on_site") && input.etaMinutes !== null) {
    const minutes = Math.min(input.etaMinutes, ETA_FIT_MINUTES);
    parts.push(clamp01(1 - minutes / ETA_FIT_MINUTES));
    notes.push(`about ${Math.max(1, Math.round(input.etaMinutes))} min away`);
  }

  if (held.has("urgent")) {
    const ready = input.onVacation
      ? 0
      : clamp01(1 - Math.min(input.workload, MAX_WORKLOAD) / MAX_WORKLOAD);
    parts.push(ready);
    notes.push(
      input.onVacation
        ? "on vacation, so not free today"
        : input.workload === 0
        ? "free today"
        : `${input.workload} job${input.workload === 1 ? "" : "s"} already today`,
    );
  }

  if (held.has("rain") && held.has("on_site") && input.distanceKm !== null) {
    parts.push(
      clamp01(1 - Math.min(input.distanceKm, SOFT_RADIUS_KM) / SOFT_RADIUS_KM),
    );
    notes.push("short ride in the rain matters");
  }

  if (parts.length === 0) {
    return { value: null, note: "No condition-specific fit to measure" };
  }

  const value = parts.reduce((sum, p) => sum + p, 0) / parts.length;
  const note = notes.join(", ");
  return { value, note: note.charAt(0).toUpperCase() + note.slice(1) };
}

/** What this client's own bookings say about this technician. */
export function clientPreferenceScore(
  history: ClientHistory,
  technicianId: string,
): { value: number | null; note: string } {
  if (history.pastJobs === 0) {
    return {
      value: null,
      note: "First booking - no preferences to learn from yet",
    };
  }

  const record = history.byTechnician.get(technicianId);
  if (!record || record.jobs === 0) {
    return {
      value: CLIENT_PREFERENCE_SCORE.not_yet,
      note: "You have not booked them before",
    };
  }

  if (record.stars !== null && record.stars >= WELL_RATED_STARS) {
    return {
      value: CLIENT_PREFERENCE_SCORE.rated_well,
      note: `You rated them ${record.stars} stars before`,
    };
  }

  if (record.stars !== null && record.stars <= POORLY_RATED_STARS) {
    return {
      value: CLIENT_PREFERENCE_SCORE.rated_poorly,
      note: `You rated them ${record.stars} star${record.stars === 1 ? "" : "s"} before`,
    };
  }

  return {
    value: CLIENT_PREFERENCE_SCORE.worked_before,
    note: `${record.jobs} earlier job${record.jobs === 1 ? "" : "s"} with you`,
  };
}

/**
 * Response behaviour and experience, averaged.
 *
 * Rating is deliberately NOT here: it is already a Stage 1 factor, and
 * counting it twice would let one number decide a ranking that is meant to
 * weigh several.
 *
 * Cancellations are not here either. `jobs` records that a job was cancelled
 * but not who cancelled it, and holding a client's change of plans against
 * the technician would be unfair. Stated as a limitation in docs/rb-cars.md.
 */
export function performanceScore(
  record: TrackRecord | undefined,
  totalJobs: number,
): { value: number; note: string; responseRate: number; answered: number } {
  const accepted = record?.accepted ?? 0;
  const declined = record?.declined ?? 0;
  const answered = accepted + declined;

  const responseRate = (accepted + RESPONSE_PRIOR_WEIGHT * RESPONSE_PRIOR) /
    (answered + RESPONSE_PRIOR_WEIGHT);

  const experience = clamp01(
    Math.log(1 + Math.max(totalJobs, 0)) /
      Math.log(1 + EXPERIENCE_SATURATION_JOBS),
  );

  const note = answered === 0
    ? `No offers answered yet; ${totalJobs} job${totalJobs === 1 ? "" : "s"} done`
    : `Accepted ${accepted} of ${answered} offers; ${totalJobs} job${
      totalJobs === 1 ? "" : "s"
    } done`;

  return {
    value: (responseRate + experience) / 2,
    note,
    responseRate: round(responseRate),
    answered,
  };
}

/** Runs Stage 3 for one technician. Rules are applied here, as for 1 and 2. */
export function scoreRecommendation(input: {
  suitability: StageResult;
  acceptance: StageResult;
  contextFit: { value: number | null; note: string };
  clientPreference: { value: number | null; note: string };
  performance: { value: number; note: string };
  multipliers: WeightMultipliers;
}): StageResult {
  const factors: FactorInput[] = [
    {
      key: "suitability",
      label: "Can do the job (Stage 1)",
      value: input.suitability.score,
      weight: RECOMMENDATION_WEIGHTS.suitability,
      note: `Suitability ${Math.round(input.suitability.score * 100)}%`,
    },
    {
      key: "acceptance",
      label: "Likely to accept (Stage 2)",
      value: input.acceptance.score,
      weight: RECOMMENDATION_WEIGHTS.acceptance,
      note: `Acceptance likelihood ${Math.round(input.acceptance.score * 100)}%`,
    },
    {
      key: "context_fit",
      label: "Fits current conditions",
      value: input.contextFit.value,
      weight: RECOMMENDATION_WEIGHTS.context_fit,
      note: input.contextFit.note,
    },
    {
      key: "client_preference",
      label: "Your history with them",
      value: input.clientPreference.value,
      weight: RECOMMENDATION_WEIGHTS.client_preference,
      note: input.clientPreference.note,
    },
    {
      key: "technician_performance",
      label: "Track record",
      value: input.performance.value,
      weight: RECOMMENDATION_WEIGHTS.technician_performance,
      note: input.performance.note,
    },
  ];

  return reweight(combine(factors), input.multipliers);
}
