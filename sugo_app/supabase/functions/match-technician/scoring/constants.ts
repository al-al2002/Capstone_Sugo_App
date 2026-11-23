/**
 * Every tunable number in RB-CARS, in one file.
 *
 * Nothing in `suitability.ts` or `acceptance.ts` contains a bare literal. If a
 * panel member asks "why 0.35?", the answer is on this page and changing it is
 * a one-line edit, not a hunt through the scoring code.
 *
 * All factor scores are normalised to 0..1 before weighting, so a stage score
 * is a weighted mean and is itself always 0..1.
 *
 * ## How the weights map to the paper (2026-11-22)
 *
 *   FINAL_WEIGHTS       = Table 10, Normalized Criterion Scores
 *   ACCEPTANCE_WEIGHTS  = Table 11, Acceptance Likelihood Signals
 *   SUITABILITY_WEIGHTS = what Table 10's "Skill relevance" is made of
 *
 * The final score is Table 10's weighted sum, `sum(W_j x C_ij)`, over five
 * criteria. Two of them are themselves weighted sums: Skill relevance (Stage
 * 1) and Acceptance likelihood (Stage 2, Table 11).
 */

// ---------------------------------------------------------------------------
// Stage 1 - Skill relevance: can this technician do this job well?
// ---------------------------------------------------------------------------

/**
 * Table 10's "Skill relevance", broken down. Must sum to 1.0. Checked at
 * module load by `assertWeightsSumToOne`.
 *
 * Until 2026-11-22 this stage also held the trust badge (0.14) and the client
 * rating (0.12). Both are criteria of their own in Table 10, so they moved up
 * to `FINAL_WEIGHTS`; keeping them here as well would count them twice. What
 * is left is purely "can they fix this", and the four weights keep roughly
 * their old proportions.
 */
export const SUITABILITY_WEIGHTS = {
  /**
   * The brand + device ladder. The heaviest factor in the stage.
   *
   * An assessed, brand-level claim - a technician who passed an assessment
   * covering this exact device and declared this exact brand - is much
   * stronger evidence than a self-typed skill tag, so it outranks `skill_tag`.
   */
  specialization: 0.45,
  /** Does a skill tag match the specific symptom? Direct, but self-declared. */
  skill_tag: 0.30,
  /** Historical diagnosis accuracy on this exact device+symptom combo. */
  diagnosis_accuracy: 0.15,
  /**
   * Standard / pro / elite - a proxy for depth of experience. The lightest,
   * because tier also drives Price fit in Stage 2.
   */
  tier: 0.10,
} as const;

/**
 * Stage 1 specialisation ladder, in the priority order the brief sets out.
 *
 * The gaps are deliberate. An assessed brand-level claim is a materially
 * different thing from a self-typed one, so the drop from `verified_*` to
 * `unverified_claim` is the largest step on the ladder - a technician who
 * merely *says* they fix Samsung aircons should never outrank one who passed
 * the assessment for it.
 *
 * Nothing here is zero: an unmatched technician stays in the pool at a low
 * score rather than being filtered out, because a client whose exact brand
 * nobody covers still needs three names.
 */
export const SPECIALIZATION_MATCH = {
  /** (a) Assessed Expert on this exact brand AND device. */
  expert_brand: 1.00,
  /** (b) Assessed Intermediate on this exact brand AND device. */
  intermediate_brand: 0.85,
  /** (c) Assessed Expert on the device, a different brand. General specialist. */
  expert_device: 0.70,
  /** (c) Assessed Intermediate on the device, a different brand. */
  intermediate_device: 0.60,
  /** (d) Declared but never assessed, on this brand or device. Still included. */
  unverified_claim: 0.35,
  /** Legacy `technicians.specialization` array only - pre-registration data. */
  legacy_array: 0.30,
  /** Nothing matches. Kept in the pool, ranked last on this factor. */
  none: 0.10,
} as const;

/**
 * Table 10's "Trust badge" criterion, by rung (see `trustRungOf`).
 *
 * Reads the Progressive Trust Badge, so scoring and the client filter share
 * one source of truth: ID verified, Skill verified and Community Trusted
 * (0.55 / 0.80 / 1.00).
 *
 * Rung 1 is not zero: identity was approved by a human, the hard requirement.
 * Rung 0 (identity approved, email never confirmed) scores the same as rung
 * 1: everyone in the pool passed the identity gate, and the missing email is
 * not a reason to bury them below it.
 */
export const TRUST_BADGE_SCORE: readonly number[] = [0.55, 0.55, 0.80, 1.00];

/** Tier maps to a 0..1 score. Elite is the ceiling, standard is mid. */
export const TIER_SCORE: Record<string, number> = {
  standard: 0.50,
  pro: 0.80,
  elite: 1.00,
};

/**
 * Cold start.
 *
 * A newly verified technician has no completed jobs, so the accuracy factor
 * has no evidence and would drag them below an established technician forever
 * - the classic cold-start trap. Two mitigations:
 *
 * 1. `COLD_START_BOOST` is added to the Stage 1 score (result clamped to 1)
 *    when the technician is verified and has zero completed jobs. Verification
 *    is the gate: an unverified newcomer gets nothing.
 * 2. Their accuracy factor uses `ACCURACY_PRIOR` rather than 0, so absence of
 *    evidence is treated as "unknown", not "bad".
 *
 * The boost decays away naturally: once `total_jobs > 0` it no longer applies,
 * and real accuracy data takes over.
 */
export const COLD_START_BOOST = 0.08;
export const COLD_START_MAX_JOBS = 0;

// ---------------------------------------------------------------------------
// Diagnosis accuracy - the Step 8 feedback loop reaching back into Stage 1
// ---------------------------------------------------------------------------

/**
 * Bayesian shrinkage toward a prior.
 *
 * Raw `correct / total` is untrustworthy on small samples: one lucky job reads
 * as 100% accuracy. We instead compute
 *
 *   (correct + PRIOR_WEIGHT * ACCURACY_PRIOR) / (total + PRIOR_WEIGHT)
 *
 * which starts every technician at `ACCURACY_PRIOR` and moves toward their
 * observed rate as evidence accumulates. With PRIOR_WEIGHT = 3, a technician
 * needs roughly three jobs before their own record outweighs the prior.
 */
export const ACCURACY_PRIOR = 0.70;
export const ACCURACY_PRIOR_WEIGHT = 3;

/**
 * Ratings are smoothed toward [RATING_PRIOR_MEAN] by this many notional jobs.
 *
 * A single five-star review is not evidence that somebody is better than a
 * technician averaging 4.7 over fifty jobs, and without smoothing it outranks
 * them outright. With a weight of 5, one perfect review lands near the prior
 * and it takes a real history to move away from it - in either direction, so a
 * newcomer with one bad day is not buried either.
 */
export const RATING_PRIOR_WEIGHT = 5;

/**
 * Where an unrated technician sits: slightly above the middle of the 1-5 scale.
 *
 * Deliberately not 0. A technician with no reviews has not been judged badly,
 * they have not been judged at all, and the cold-start rule in Stage 1 exists
 * precisely so an empty history does not lock someone out.
 */
export const RATING_PRIOR_MEAN = 4.0;

/** The rating scale stored in `technicians.rating`. */
export const RATING_MIN = 1;
export const RATING_MAX = 5;

/**
 * A mid-job reroute means the on-site path was the wrong call. It costs the
 * client a wasted visit, so it discounts the accuracy signal proportionally to
 * how often it happens.
 */
export const REROUTE_PENALTY = 0.30;

/** Outcomes on the same device type but a different symptom count for less. */
export const SAME_DEVICE_ONLY_WEIGHT = 0.4;

// ---------------------------------------------------------------------------
// Stage 2 - Acceptance likelihood: will this technician take it, and turn up?
// ---------------------------------------------------------------------------

/**
 * Table 11, Acceptance Likelihood Signals. Must sum to 1.0.
 *
 * Every signal here differs from one technician to the next on the same job.
 * That is the rule the table was rebuilt on (2026-11-22): the old stage also
 * scored traffic, weather, urgency x path and client reliability as values
 * measured once per job, so every candidate got the same number and none of
 * them could change who ranked first. Traffic and weather now act through
 * each technician's own travel time; urgency acts through the matching rules.
 *
 * Availability (on vacation or not) is not here: it is its own criterion in
 * Table 10 (`FINAL_WEIGHTS.availability`), and counting it in both places
 * would score it twice.
 */
export const ACCEPTANCE_WEIGHTS = {
  /**
   * Traffic-adjusted travel time to the task location: distance from their
   * base at the live TomTom speed. The heaviest signal - the clearest sign of
   * whether someone will actually come, and the one that varies most.
   */
  travel_burden: 0.30,
  /** How many active bookings they already hold. Also what spreads work. */
  workload: 0.25,
  /**
   * Whether the task's fixed price meets the technician's rate. Replaced
   * Budget fit when SUGO moved to fixed prices: the client no longer states a
   * budget, so the question became whether this price is worth this
   * technician's time. See `PRICE_FIT_MIN_PHP`.
   */
  price_fit: 0.20,
  /** Whether the task falls within the service area they declared. */
  coverage_fit: 0.15,
  /**
   * Weather & traffic readiness (was "Weather readiness" until 2026-11-22):
   * will they actually travel in the current rain and traffic? Decided by
   * the technician's own registration answers when it is raining or the
   * traffic is heavy (see `TRAVEL_WILLINGNESS`), estimated from the weather
   * and their trip otherwise. Light, because on a clear, quiet day it is 1.0
   * for everyone; the rain and traffic rules raise it exactly when it
   * matters.
   */
  conditions_readiness: 0.10,
} as const;

/**
 * What the technician said at registration (20261122000001), as a 0..1
 * readiness for each condition. 1 = they said they go; 0 = they said they
 * do not. Used only while that condition holds at the job; a technician who
 * has not answered (null) is estimated from the weather and their trip, as
 * before the question existed.
 *
 * `technicians.rain_travel`:
 *   any        yes, even in heavy rain or a storm
 *   not_heavy  yes in rain, not in heavy rain or a storm
 *   never      not in the rain
 */
export const RAIN_TRAVEL_READINESS: Record<
  string,
  { rain: number; heavyRain: number }
> = {
  any: { rain: 1, heavyRain: 1 },
  not_heavy: { rain: 1, heavyRain: 0 },
  never: { rain: 0, heavyRain: 0 },
};

/**
 * How exposed each service path is to travel conditions.
 *
 * A home service is fully exposed: the technician rides through the rain and
 * the traffic to reach the client. A pickup is partly exposed - one trip, at a
 * time of their choosing. An IT community job is remote, so travel barely
 * matters. Travel burden and weather readiness are both scaled by this.
 */
export const TRAVEL_EXPOSURE: Record<string, number> = {
  home_service: 1.00,
  pickup: 0.60,
  it_community: 0.10,
};

/** Workload at or above this is treated as fully booked (score 0). */
export const MAX_WORKLOAD = 5;

/**
 * Beyond this radius a technician is dropped from the pool entirely, and the
 * point at which Coverage fit reaches 0 for someone past their own radius.
 */
export const HARD_RADIUS_KM = 50;

/**
 * Travel time, in minutes, at which Travel burden reaches 0. Also the trip
 * length that counts as "the whole trip" when Weather & traffic readiness is
 * estimated for a technician who has not answered.
 */
export const TRAVEL_BURDEN_MAX_MINUTES = 60;

/**
 * The smallest fixed price each tier usually takes, in PHP (2026-11-22).
 *
 * Price fit is 1.0 at or above it. The fixed prices run from ₱300 to ₱3,500,
 * most of them ₱500-₱600, so:
 *
 * - standard (₱300) - every job in the catalogue meets it;
 * - pro (₱500)      - meets most jobs, dips on the ₱300-₱450 quick fixes;
 * - elite (₱800)    - only the bigger jobs meet it in full.
 *
 * That is the acceptance question this signal asks: an elite technician
 * offered ₱500 for a slow laptop is less likely to take it than a standard
 * one. Placeholder figures until real ones are agreed; one edit here.
 */
export const PRICE_FIT_MIN_PHP: Record<string, number> = {
  standard: 300,
  pro: 500,
  elite: 800,
};

/**
 * Below the minimum, Price fit falls linearly and reaches 0 at this share of
 * it: at 0.5, a price half the tier's minimum scores 0.
 */
export const PRICE_FIT_ZERO_RATIO = 0.5;

/**
 * Price fit when the symptom has no single fixed price ("I am not sure", or a
 * per-camera fee). Neutral - neither helps nor harms.
 */
export const NEUTRAL_PRICE_FIT = 0.70;

// ---------------------------------------------------------------------------
// Final score - Table 10, Normalized Criterion Scores
// ---------------------------------------------------------------------------

/**
 * Table 10. The final score, and the ranking, is `sum(W_j x C_ij)` over these
 * five criteria. Must sum to 1.0.
 *
 * Rebuilt on 2026-11-22 to match the paper. Before that the final layer was
 * suitability 0.45, acceptance 0.20, context fit 0.15, client history 0.10
 * and track record 0.10, with rating and the trust badge buried inside Stage
 * 1. Two things changed beyond the regrouping:
 *
 * - Table 10's "Location proximity" became "Acceptance likelihood". Location
 *   is scored inside Table 11 (Travel burden, Coverage fit); keeping it here
 *   as well would count distance twice. The old "context fit" re-scored
 *   service area, travel time and readiness - the same double count - so it
 *   went into Stage 2 too.
 * - Client history and track record left the score. Neither is in the paper.
 *   Both are still shown to the client as reasons ("You rated them 5 stars
 *   last time", "Usually accepts the jobs they are offered").
 *
 * Skill relevance stays the heaviest: a technician who is close, free and
 * cheap but cannot fix the device is a worse outcome than a slightly slower
 * one who can.
 */
export const FINAL_WEIGHTS = {
  /** Skill relevance - Stage 1, whole. Can they do this repair well? */
  suitability: 0.45,
  /** Acceptance likelihood - Stage 2 (Table 11), whole. */
  acceptance: 0.40,
  /** User rating - what past clients said, smoothed. */
  rating: 0.05,
  /** Availability - 0 while on vacation; `job-response` refuses the booking. */
  availability: 0.05,
  /** Trust badge - the Progressive Trust Badge rung for this job's device. */
  trust_badge: 0.05,
} as const;

/**
 * Response behaviour: how often a technician accepts the offers they are sent.
 * No longer scored (not in Table 10); used only to earn the "Usually accepts
 * the jobs they are offered" reason.
 *
 * Smoothed toward a prior exactly like diagnosis accuracy, and for the same
 * reason - one decline from a newcomer is not a 0% response rate. With a
 * weight of 3, it takes about three answered offers before their own record
 * outweighs the prior.
 */
export const RESPONSE_PRIOR = 0.75;
export const RESPONSE_PRIOR_WEIGHT = 3;

// ---------------------------------------------------------------------------
// Context signals - the conditions the matching rules are written against
// ---------------------------------------------------------------------------

/** TomTom congestion at or above this is "heavy traffic" (its own label). */
export const HEAVY_TRAFFIC_CONGESTION = 0.6;

/**
 * Weather severity at or above this counts as "rain" for the rules. 0.5 sits
 * above drizzle (0.35) and mist (0.30) and below rain (0.55), so a grey
 * afternoon does not re-weight anybody but a real downpour does.
 */
export const RAIN_SEVERITY = 0.5;

/**
 * Weather severity at or above this is "heavy rain" for the rules
 * (2026-11-22): OpenWeatherMap's heavy and extreme rain (0.85) and
 * thunderstorms (1.00). Ordinary rain (0.55) stays below it, so a downpour
 * re-weights the ranking harder than a shower does. A heavy-rain job also
 * holds `rain`, so both rain rules fire and their multipliers compose.
 */
export const HEAVY_RAIN_SEVERITY = 0.85;

/**
 * No factor's weight can be multiplied by more than this, however many rules
 * fire. Without a cap, three rules that each boost proximity would compound
 * into a ranking that is about distance and nothing else.
 */
export const MAX_RULE_MULTIPLIER = 2.0;

/** How many offers we write to `job_matches`. The check constraint allows 1-3. */
export const TOP_N = 3;

/**
 * Step 5 of the paper, Previous Provider Priority (built 2026-11-22). A
 * technician the client has completed a job with before is moved to the top
 * of the list when they still rate this high overall...
 */
export const PREVIOUS_TECHNICIAN_MIN_RATING = 4.5;

/**
 * ...and the client's own last rating of them, if they left one, is at least
 * this. Someone the client rated 3 stars or below is never pushed back at
 * them, whatever their average.
 */
export const PREVIOUS_TECHNICIAN_MIN_CLIENT_STARS = 4;

/**
 * Two technicians whose final scores differ by less than this are treated as
 * equally good, and the one with the lighter workload is ranked higher. This is
 * the workload-aware ranking in the brief: it spreads jobs across similarly
 * qualified technicians instead of sending every job to the single highest
 * scorer until they are saturated.
 */
export const SCORE_TIE_EPSILON = 0.03;

/**
 * Below this recommendation score we would rather show fewer than three bad
 * options.
 */
export const MIN_VIABLE_SCORE = 0.20;

// ---------------------------------------------------------------------------
// Weather severity, keyed on the OpenWeatherMap condition id group
// ---------------------------------------------------------------------------

/** 0 = perfect conditions, 1 = do not send anyone outside. */
export const WEATHER_SEVERITY = {
  thunderstorm: 1.00, // 2xx
  drizzle: 0.35, // 3xx
  rain: 0.55, // 5xx
  heavyRain: 0.85, // 502-504, 522, 531
  snow: 0.90, // 6xx
  atmosphere: 0.30, // 7xx - mist, haze, fog, ash
  clear: 0.00, // 800
  clouds: 0.10, // 80x
  unknown: 0.20,
} as const;

// ---------------------------------------------------------------------------
// External API behaviour
// ---------------------------------------------------------------------------

/** Give up on TomTom / OpenWeatherMap after this, rather than stalling a match. */
export const EXTERNAL_API_TIMEOUT_MS = 4000;

/**
 * Traffic is sampled once per job at the client's coordinate, not once per
 * technician. One request instead of N, and congestion around the destination
 * is what actually determines arrival time.
 */
export const TRAFFIC_ZOOM = 10;

// ---------------------------------------------------------------------------
// Guard
// ---------------------------------------------------------------------------

function assertWeightsSumToOne(
  name: string,
  weights: Record<string, number>,
): void {
  const total = Object.values(weights).reduce((sum, w) => sum + w, 0);
  if (Math.abs(total - 1) > 1e-9) {
    throw new Error(
      `${name} weights must sum to 1.0, got ${total.toFixed(4)}. ` +
        `A stage score would no longer be on a 0..1 scale.`,
    );
  }
}

assertWeightsSumToOne("SUITABILITY_WEIGHTS", SUITABILITY_WEIGHTS);
assertWeightsSumToOne("ACCEPTANCE_WEIGHTS", ACCEPTANCE_WEIGHTS);
assertWeightsSumToOne("FINAL_WEIGHTS", FINAL_WEIGHTS);
