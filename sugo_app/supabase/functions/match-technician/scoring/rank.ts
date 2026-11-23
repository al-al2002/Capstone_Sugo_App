/**
 * Runs the three stages for one technician, builds the explanations, and ranks.
 *
 * This is the module that produces the `score_breakdown` jsonb the client
 * review screen reads, so it is where "why was I shown this person?" gets its
 * answer.
 *
 * Per candidate, in the brief's order:
 *
 *   Stage 1 skill relevance       ->  re-weighted by the job's matching rules
 *   Stage 2 acceptance likelihood ->  re-weighted by the job's matching rules
 *   Final score, Table 10 (skill, acceptance, rating, availability, badge)
 *   reasons for the client, from the numbers above
 */
import {
  FINAL_WEIGHTS,
  MIN_VIABLE_SCORE,
  PREVIOUS_TECHNICIAN_MIN_CLIENT_STARS,
  PREVIOUS_TECHNICIAN_MIN_RATING,
  SCORE_TIE_EPSILON,
  TRAVEL_EXPOSURE,
} from "./constants.ts";
import { round } from "./weighting.ts";
import { scoreSuitability } from "./suitability.ts";
import { scoreAcceptance } from "./acceptance.ts";
import { defaultAccuracy } from "./accuracy.ts";
import { reweight } from "./rules.ts";
import {
  availabilityScore,
  formatAwayUntil,
  ratingScore,
  responseRecord,
  scoreRecommendation,
  trustBadgeScore,
} from "./recommendation.ts";
import { buildReasons } from "./reasons.ts";
import { trustBadgeForJob, trustRungOf } from "./preferences.ts";
import type {
  AccuracyStats,
  ClientHistory,
  ConsideredCandidate,
  JobContext,
  RecommendationReason,
  JobRow,
  JobSnapshot,
  ScoredCandidate,
  ServicePath,
  TechnicianRow,
  TechnicianSnapshot,
  TrackRecord,
} from "./types.ts";

/**
 * Copies the job into the jsonb so the *technician* can read it under RLS.
 *
 * Client identity and exact coordinates are left out on purpose - see the
 * `JobSnapshot` doc comment.
 */
function jobSnapshot(job: JobRow, servicePath: ServicePath): JobSnapshot {
  return {
    id: job.id,
    device_type: job.device_type,
    brand: job.brand,
    device_detail: job.device_detail,
    problem_symptom: job.problem_symptom,
    has_physical_damage: job.has_physical_damage,
    classification_confidence: job.classification_confidence,
    service_path: servicePath,
    urgency: job.urgency,
    budget_min: job.budget_min,
    budget_max: job.budget_max,
    preferred_schedule: job.preferred_schedule,
    description: job.description,
    photo_urls: job.photo_urls ?? [],
    delivery_option: job.delivery_option ?? null,
  };
}

/** Copies the technician into the jsonb so a client can read it under RLS. */
function snapshot(
  technician: TechnicianRow,
  matchedSpecializations: string[],
  deviceCandidates: string[],
): TechnicianSnapshot {
  return {
    id: technician.id,
    // `matching_candidates` flattens the profile columns; the nested `profiles`
    // shape is the older embed, kept as a fallback.
    full_name: technician.full_name ?? technician.profiles?.full_name ?? null,
    avatar_url: technician.avatar_url ?? technician.profiles?.avatar_url ?? null,
    tier: technician.tier,
    badge: technician.badge,
    is_verified: technician.is_verified,
    // Now "not on vacation". Kept under the old name because installed
    // builds of the app still read it and print "Offline" when it is false;
    // sending the old switch's leftover value would label working people.
    is_available: !technician.away_until,
    rating: technician.rating ?? 0,
    total_jobs: technician.total_jobs ?? 0,
    current_workload: technician.current_workload ?? 0,
    specialization: technician.specialization ?? [],
    skill_tags: technician.skill_tags ?? [],
    member_since: technician.created_at,
    latitude: technician.latitude,
    longitude: technician.longitude,
    barangay: technician.barangay ?? null,
    verification_tier: technician.verification_tier ?? "basic",
    // The trust badge for THIS job - what the match card prints.
    trust_badge_for_job: trustBadgeForJob(technician, deviceCandidates),
    // The exact brands that earned this match, so the review screen can say
    // "Assessed on Samsung aircon" instead of only showing a number.
    matched_specializations: matchedSpecializations,
    // Drives the card's "On vacation until ..." label and its disabled button.
    away_until: technician.away_until ?? null,
  };
}

/**
 * Builds the short phrases behind "Matched because: ...".
 *
 * Ordered strongest-evidence-first and capped, because a card has one line.
 * Every phrase is derived from a real number in the breakdown - none of them
 * is decorative copy.
 */
export function buildExplainability(
  accuracy: AccuracyStats,
  distanceKm: number | null,
  workload: number,
  coldStart: boolean,
  context: JobContext,
  technician: TechnicianRow,
  job: JobRow,
  matchedSpecializations: string[],
): string[] {
  const parts: string[] = [];

  // Strongest evidence first, and since 20260907000010 that is the brand-level
  // match rather than the repair count: "assessed on your exact machine" is
  // what a client is actually looking for.
  const assessedOnBrand = (technician.specializations ?? []).some((s) =>
    s.verified &&
    context.deviceCandidates.includes(s.device_type) &&
    job.brand !== null &&
    s.brand.trim().toLowerCase() === job.brand.trim().toLowerCase()
  );

  if (assessedOnBrand && job.brand) {
    parts.push(`assessed on ${job.brand}`);
  } else if (matchedSpecializations.length > 0) {
    parts.push(`covers ${matchedSpecializations[0].replace("/", " ")}`);
  }

  // The top rung of the Progressive Trust Badge, for this job's device.
  if (trustRungOf(technician, context.deviceCandidates) === 3) {
    parts.push("Community Trusted");
  }

  if (accuracy.similarRepairs > 0) {
    parts.push(
      `${accuracy.similarRepairs} similar repair${
        accuracy.similarRepairs === 1 ? "" : "s"
      }`,
    );
  } else if (accuracy.sameDeviceRepairs > 0) {
    parts.push(`${accuracy.sameDeviceRepairs} jobs on the same device type`);
  } else if (coldStart) {
    parts.push("newly verified technician");
  }

  if (distanceKm !== null) {
    parts.push(
      distanceKm < 1
        ? `${Math.round(distanceKm * 1000)}m away`
        : `${distanceKm.toFixed(1)}km away`,
    );
  }

  // Said before the schedule, because "cannot be booked" changes how the
  // client reads everything after it.
  if (technician.away_until) {
    parts.push(`on vacation until ${formatAwayUntil(technician.away_until)}`);
  } else if (workload === 0) {
    parts.push("available today");
  } else if (workload <= 2) {
    parts.push("light schedule today");
  }

  if ((technician.rating ?? 0) >= 4.5 && (technician.total_jobs ?? 0) >= 5) {
    parts.push(`rated ${(technician.rating ?? 0).toFixed(1)}`);
  }

  if (context.traffic.available && context.traffic.label) {
    parts.push(context.traffic.label);
  }

  if (
    context.weather.available &&
    (context.weather.severity ?? 0) > 0.4 &&
    context.travelExposure > 0.5
  ) {
    parts.push(`willing to travel in ${context.weather.description}`);
  }

  return parts.slice(0, 5);
}

/** Scores one technician end to end. */
export function scoreCandidate(
  job: JobRow,
  technician: TechnicianRow,
  context: JobContext,
  distanceKm: number | null,
  accuracyIndex: Map<string, AccuracyStats>,
  trackRecords: Map<string, TrackRecord> = new Map(),
): ScoredCandidate {
  const accuracy = accuracyIndex.get(technician.id) ?? defaultAccuracy();
  const { multipliers } = context.rules;

  // ------------------------------------------------ Stages 1 and 2, re-weighted
  //
  // Each stage is scored on its base weights, then the job's matching rules
  // shift those weights (Step 3). Both versions are kept in the factors - the
  // weight applied and, where a rule moved it, `base_weight` - so the demo
  // view can show exactly what the situation changed.
  const scored1 = scoreSuitability(job, technician, accuracy, context);
  const suitability = reweight(scored1.stage, multipliers.suitability);
  const { coldStartApplied, matchedSpecializations } = scored1;

  const scored2 = scoreAcceptance(job, technician, context, distanceKm);
  const acceptance = reweight(scored2.stage, multipliers.acceptance);
  const { pricePhp, workload, etaMinutes } = scored2;

  // ------------------------------------------------- Final score, Table 10
  const recommendationStage = scoreRecommendation({
    suitability,
    acceptance,
    rating: ratingScore(technician),
    availability: availabilityScore(technician),
    trustBadge: trustBadgeScore(technician, context.deviceCandidates),
    multipliers: multipliers.recommendation,
  });

  // Facts for the reasons only - neither is a Table 10 criterion.
  const history = context.clientHistory.byTechnician.get(technician.id);
  const response = responseRecord(trackRecords.get(technician.id));

  const reasons = buildReasons({
    job,
    technician,
    suitability,
    acceptance,
    accuracy,
    signals: context.rules.signals,
    distanceKm,
    etaMinutes,
    workload,
    coldStart: coldStartApplied,
    history,
    responseRate: response.responseRate,
    answeredOffers: response.answered,
  });

  // Table 10's weighted sum IS the final score: it is what ranks the list.
  const finalScore = recommendationStage.score;

  const recommendation = {
    ...recommendationStage,
    signals: context.rules.signals,
    rules: context.rules.applied,
    reasons,
  };

  const explainability = buildExplainability(
    accuracy,
    distanceKm,
    workload,
    coldStartApplied,
    context,
    technician,
    job,
    matchedSpecializations,
  );

  return {
    technician,
    suitability,
    acceptance,
    recommendation,
    finalScore,
    distanceKm,
    accuracy,
    breakdown: {
      // 3 since 2026-11-22: Stage 1 is Skill relevance, Stage 2 is Table 11,
      // and `recommendation` is Table 10's final score.
      version: 3,
      stage1: suitability,
      stage2: acceptance,
      recommendation,
      final_score: finalScore,
      context: {
        distance_km: distanceKm === null ? null : round(distanceKm, 2),
        eta_minutes: round(etaMinutes ?? 0, 1),
        similar_repairs: accuracy.similarRepairs,
        same_device_repairs: accuracy.sameDeviceRepairs,
        diagnosis_accuracy: accuracy.signal,
        reroute_rate: accuracy.rerouteRate,
        workload,
        is_cold_start: coldStartApplied,
        // The fixed price Price fit compared: labor plus any urgent fee.
        // Replaced `indicative_quote_php` (tier rate x 3 hours) on 2026-11-22.
        fixed_price_php: pricePhp,
        service_path: context.servicePath,
        urgency: job.urgency,
        // Distance and ETA are now measured from the technician's registered
        // base rather than a stale live position.
        measured_from: technician.base_latitude !== null &&
            technician.base_longitude !== null
          ? "base_location"
          : "live_position",
        service_radius_km: technician.service_radius_km,
        verification_tier: technician.verification_tier ?? "basic",
        matched_specializations: matchedSpecializations,
        client_trust_level: context.clientTrust.trustLevel,
        client_no_show_count: context.clientTrust.noShowCount,
        traffic: context.traffic,
        weather: context.weather,
        // Table 10's base weights. Version 2 held the five-part
        // recommendation layer; version 1 the two-stage split (0.60 / 0.40).
        weights: FINAL_WEIGHTS,
      },
      explainability,
      technician: snapshot(technician, matchedSpecializations, context.deviceCandidates),
      job: jobSnapshot(job, context.servicePath),
    },
  };
}

/**
 * Ranks every scored candidate. The caller takes the Top 3 from the front.
 *
 * ## Workload-aware ranking
 *
 * A plain `sort by finalScore desc` sends every job to whoever scores highest
 * until they are saturated, which is bad for the client (that technician is now
 * busy and slow) and bad for the marketplace (nobody else builds a history, so
 * nobody else ever ranks). Here, two candidates within `SCORE_TIE_EPSILON` of
 * each other are treated as equally good and the lighter-loaded one is ranked
 * first. Work spreads across similarly qualified technicians without ever
 * putting a genuinely worse match above a better one.
 *
 * ## Why nothing is cut here
 *
 * `job_matches.rank` is checked between 1 and 3, so only the first three are
 * ever written as offers - the caller takes that slice. The rest are returned
 * so the client can see the whole pool it was ranked against, which is the one
 * place fourth place onward is visible at all.
 */
export function rankAll(
  candidates: ScoredCandidate[],
): ScoredCandidate[] {
  const viable = candidates.filter(
    (candidate) => candidate.finalScore >= MIN_VIABLE_SCORE,
  );

  const pool = viable.length > 0 ? viable : candidates;

  const sorted = [...pool].sort((a, b) => {
    const gap = b.finalScore - a.finalScore;

    if (Math.abs(gap) < SCORE_TIE_EPSILON) {
      const workloadA = a.technician.current_workload ?? 0;
      const workloadB = b.technician.current_workload ?? 0;
      if (workloadA !== workloadB) return workloadA - workloadB;

      // Still tied: prefer the closer technician, then the better rated.
      const distanceA = a.distanceKm ?? Number.MAX_SAFE_INTEGER;
      const distanceB = b.distanceKm ?? Number.MAX_SAFE_INTEGER;
      if (distanceA !== distanceB) return distanceA - distanceB;

      return (b.technician.rating ?? 0) - (a.technician.rating ?? 0);
    }

    return gap;
  });

  return sorted;
}

/**
 * Step 5 of the paper - Previous Provider Priority (built 2026-11-22).
 *
 * A client who has had a job done by a technician before, and was happy with
 * it, usually wants them again. So after ranking, one technician is moved to
 * the top of the list when ALL of these hold:
 *
 * - the client has a **completed** job with them (`clientHistory`);
 * - they are **in this job's pool at all** - every gate passed, every client
 *   preference met - because the move happens on the ranked list, not before
 *   the gates;
 * - their overall rating is at least `PREVIOUS_TECHNICIAN_MIN_RATING` (4.5);
 * - the client's own last rating of them, if any, is at least
 *   `PREVIOUS_TECHNICIAN_MIN_CLIENT_STARS` (4);
 * - they are **not on vacation** - a technician who cannot be booked is never
 *   put first.
 *
 * When several qualify, the best-ranked of them moves up. Their score is NOT
 * changed: the number on the card stays the honest weighted sum, and the
 * reason says why they are first anyway. The paper wrote this for "recurring
 * tasks"; SUGO has no recurring tasks, so a repeat booking is the case.
 */
export function applyPreviousTechnicianPriority(
  ranked: ScoredCandidate[],
  history: ClientHistory,
): ScoredCandidate[] {
  if (history.pastJobs === 0) return ranked;

  const index = ranked.findIndex((candidate) => {
    const record = history.byTechnician.get(candidate.technician.id);
    if (!record || record.completed < 1) return false;
    if (record.stars !== null && record.stars < PREVIOUS_TECHNICIAN_MIN_CLIENT_STARS) {
      return false;
    }
    if ((candidate.technician.rating ?? 0) < PREVIOUS_TECHNICIAN_MIN_RATING) return false;
    return !candidate.technician.away_until;
  });

  if (index < 0) return ranked;

  const chosen = ranked[index];
  const reason: RecommendationReason = {
    code: "previous_technician",
    text: "You booked them before, so they are shown first",
    kind: "positive",
  };
  const recommendation = {
    ...chosen.recommendation,
    reasons: [reason, ...chosen.recommendation.reasons],
    previous_technician: true,
  };
  const promoted: ScoredCandidate = {
    ...chosen,
    recommendation,
    breakdown: { ...chosen.breakdown, recommendation },
  };

  return [promoted, ...ranked.slice(0, index), ...ranked.slice(index + 1)];
}

/**
 * Flattens a ranked candidate into the row the client list renders.
 *
 * Deliberately thin: a name, a distance and the three scores. The full
 * `score_breakdown` is only carried for the three that became offers, because
 * shipping every factor for every technician would put the whole pool's
 * scoring detail on a screen nobody asked for it on.
 */
export function toConsidered(
  candidate: ScoredCandidate,
  index: number,
  offered: boolean,
): ConsideredCandidate {
  const context = candidate.breakdown.context as Record<string, unknown>;

  return {
    technician_id: candidate.technician.id,
    full_name: candidate.technician.full_name ??
      candidate.technician.profiles?.full_name ?? null,
    avatar_url: candidate.technician.avatar_url ??
      candidate.technician.profiles?.avatar_url ?? null,
    rank: index + 1,
    offered,
    distance_km: candidate.distanceKm === null
      ? null
      : round(candidate.distanceKm, 2),
    eta_minutes: (context.eta_minutes as number | null) ?? null,
    available: !candidate.technician.away_until,
    suitability: candidate.suitability.score,
    acceptance: candidate.acceptance.score,
    recommendation: candidate.finalScore,
    final_score: candidate.finalScore,
    explainability: candidate.breakdown.explainability,
  };
}

/** Travel exposure for the path this job took, defaulting to home service. */
export function exposureFor(path: ServicePath | null): number {
  if (!path) return TRAVEL_EXPOSURE.home_service;
  return TRAVEL_EXPOSURE[path] ?? TRAVEL_EXPOSURE.home_service;
}
