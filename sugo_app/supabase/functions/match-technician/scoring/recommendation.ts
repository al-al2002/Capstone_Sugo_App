/**
 * The final score - Table 10, Normalized Criterion Scores.
 *
 *   Final_i = sum over j of (W_j x C_ij)
 *
 * | Criterion             | W_j  | C_ij comes from                              |
 * |-----------------------|------|----------------------------------------------|
 * | Skill relevance       | 0.45 | Stage 1 (`suitability.ts`), whole            |
 * | Acceptance likelihood | 0.40 | Stage 2 (`acceptance.ts`, Table 11), whole   |
 * | User rating           | 0.05 | `ratingScore`, smoothed toward a prior       |
 * | Availability          | 0.05 | `availabilityScore`, 0 while on vacation     |
 * | Trust badge           | 0.05 | `trustBadgeScore`, the badge rung for the job |
 *
 * Every C_ij is already on 0..1 - the "normalized" in the table's title - so
 * the final score is a weighted mean on 0..1 too. It is what the Top 3 is
 * ranked by, and it is stored as `job_matches.final_score`. The breakdown
 * keeps the key `recommendation` for it so installed app builds still read it.
 *
 * The paper's worked example (Provider A 0.879, Provider B 0.8185) is pinned
 * in `recommendation.test.ts`, so the code cannot drift from the table.
 *
 * Pure: no Deno APIs, no network.
 */
import {
  FINAL_WEIGHTS,
  RATING_MAX,
  RATING_MIN,
  RATING_PRIOR_MEAN,
  RATING_PRIOR_WEIGHT,
  RESPONSE_PRIOR,
  RESPONSE_PRIOR_WEIGHT,
  TRUST_BADGE_SCORE,
} from "./constants.ts";
import { clamp01 } from "./geo.ts";
import { trustRungOf } from "./preferences.ts";
import { reweight } from "./rules.ts";
import { combine, type FactorInput, round } from "./weighting.ts";
import type {
  StageResult,
  TechnicianRow,
  TrackRecord,
  WeightMultipliers,
} from "./types.ts";

/**
 * User rating: what previous clients said, smoothed so a thin history cannot
 * dominate.
 *
 * `technicians.rating` is a plain average, and an average over one job is
 * nearly noise: a single five-star review would otherwise outrank a technician
 * holding 4.7 across fifty. The rating is pulled toward
 * [RATING_PRIOR_MEAN] by [RATING_PRIOR_WEIGHT] notional jobs, so it takes a
 * real history to move away from the prior in either direction.
 *
 * A technician with no ratings at all scores the prior exactly. That is on
 * purpose: they have not been judged badly, they have not been judged, and the
 * cold-start rule exists so an empty history does not lock somebody out.
 */
export function ratingScore(
  technician: TechnicianRow,
): { value: number; note: string } {
  const average = technician.rating ?? 0;
  const jobs = technician.total_jobs ?? 0;

  // A zero here means "never rated", not "rated zero" - the column defaults to
  // 0 and the scale starts at 1. Feeding it in as a real score would punish
  // every new technician for work they have not done yet.
  const rated = average > 0 ? jobs : 0;

  const smoothed = (average * rated + RATING_PRIOR_MEAN * RATING_PRIOR_WEIGHT) /
    (rated + RATING_PRIOR_WEIGHT);

  const value = clamp01(
    (smoothed - RATING_MIN) / (RATING_MAX - RATING_MIN),
  );

  const note = rated === 0
    ? "No client ratings yet"
    : `${average.toFixed(1)} from ${rated} job${rated === 1 ? "" : "s"}`;

  return { value, note };
}

/**
 * `2026-09-27` -> `Sep 27`.
 *
 * The value is a calendar date with no time, so it is parsed and printed in
 * UTC: formatting it in any other zone can shift it a day either way.
 */
export function formatAwayUntil(isoDate: string): string {
  const date = new Date(`${isoDate}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return isoDate;
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  });
}

/**
 * Availability: can the technician take this job, going by their own
 * calendar?
 *
 * Decided by time off alone since 2026-09-22, when the online/offline switch
 * was removed from the app. The switch asked technicians to remember to flip
 * it many times a day, and one left off by accident kept a qualified person
 * at the bottom of every ranking with no one noticing. Vacation days are
 * planned once, end on their own, and are what a client actually needs to
 * know: whether this person can be booked.
 *
 * `technicians.is_available` still exists - the table is frozen - but nothing
 * reads it any more, so a value left over from the old switch cannot affect
 * a ranking.
 *
 * Binary on purpose. There is no honest middle value between "can be booked"
 * and "cannot". A score rather than a gate: a technician who is the only
 * expert on the client's exact machine is worth showing with an "On vacation"
 * label, so the client understands why they cannot have them, rather than
 * hiding them so the Top 3 comes back empty. `job-response` refuses the
 * booking.
 */
export function availabilityScore(
  technician: TechnicianRow,
): { value: number; note: string } {
  if (technician.away_until) {
    return {
      value: 0,
      note: `On vacation until ${formatAwayUntil(technician.away_until)}, so cannot be booked`,
    };
  }

  return { value: 1, note: "Taking jobs - no time off booked" };
}

/**
 * Trust badge: the Progressive Trust Badge rung as it applies to this job's
 * device (`trustRungOf`) - the same rung the client's "minimum trust badge"
 * preference is checked against.
 */
export function trustBadgeScore(
  technician: TechnicianRow,
  deviceCandidates: string[],
): { value: number; note: string } {
  const rung = trustRungOf(technician, deviceCandidates);

  const note = rung === 3
    ? "Community Trusted: proven on this device, with a strong track record"
    : rung === 2
    ? "Skill verified for this device"
    : technician.badge === "community_trusted" ||
        technician.badge === "skill_verified"
    ? "ID verified for this job: not yet skill verified on this device"
    : "ID verified";

  return { value: TRUST_BADGE_SCORE[rung] ?? TRUST_BADGE_SCORE[1], note };
}

/**
 * How often a technician accepts the offers they are sent, smoothed toward
 * `RESPONSE_PRIOR`.
 *
 * Not a criterion in Table 10, so it adds nothing to the score. It is kept
 * only to earn the "Usually accepts the jobs they are offered" reason, which
 * is a fact worth telling the client.
 */
export function responseRecord(
  record: TrackRecord | undefined,
): { responseRate: number; answered: number } {
  const accepted = record?.accepted ?? 0;
  const declined = record?.declined ?? 0;
  const answered = accepted + declined;

  const responseRate = (accepted + RESPONSE_PRIOR_WEIGHT * RESPONSE_PRIOR) /
    (answered + RESPONSE_PRIOR_WEIGHT);

  return { responseRate: round(responseRate), answered };
}

/**
 * The final score for one technician - Table 10. Matching rules apply here,
 * as they do to Stages 1 and 2.
 */
export function scoreRecommendation(input: {
  suitability: StageResult;
  acceptance: StageResult;
  rating: { value: number; note: string };
  availability: { value: number; note: string };
  trustBadge: { value: number; note: string };
  multipliers: WeightMultipliers;
}): StageResult {
  const factors: FactorInput[] = [
    {
      key: "suitability",
      label: "Skill relevance",
      value: input.suitability.score,
      weight: FINAL_WEIGHTS.suitability,
      note: `Stage 1 score ${Math.round(input.suitability.score * 100)}%`,
    },
    {
      key: "acceptance",
      label: "Acceptance likelihood",
      value: input.acceptance.score,
      weight: FINAL_WEIGHTS.acceptance,
      note: `Stage 2 score ${Math.round(input.acceptance.score * 100)}%`,
    },
    {
      key: "rating",
      label: "User rating",
      value: input.rating.value,
      weight: FINAL_WEIGHTS.rating,
      note: input.rating.note,
    },
    {
      key: "availability",
      label: "Availability",
      value: input.availability.value,
      weight: FINAL_WEIGHTS.availability,
      note: input.availability.note,
    },
    {
      key: "trust_badge",
      label: "Trust badge",
      value: input.trustBadge.value,
      weight: FINAL_WEIGHTS.trust_badge,
      note: input.trustBadge.note,
    },
  ];

  return reweight(combine(factors), input.multipliers);
}
