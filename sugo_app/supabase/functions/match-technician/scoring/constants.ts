/**
 * Every tunable number in RB-CARS, in one file.
 *
 * Nothing in `suitability.ts` or `acceptance.ts` contains a bare literal. If a
 * panel member asks "why 0.35?", the answer is on this page and changing it is
 * a one-line edit, not a hunt through the scoring code.
 *
 * All factor scores are normalised to 0..1 before weighting, so a stage score
 * is a weighted mean and is itself always 0..1.
 */

// ---------------------------------------------------------------------------
// Stage 1 - Suitability: can this technician do this job well?
// ---------------------------------------------------------------------------

/** Must sum to 1.0. Checked at module load by `assertWeightsSumToOne`. */
export const SUITABILITY_WEIGHTS = {
  /** Does a skill tag match the specific symptom? The most direct evidence. */
  skill_tag: 0.22,
  /**
   * The brand + device ladder. Now the heaviest single factor.
   *
   * It was 0.25 when it only asked "do they list this device type?". It is now
   * an assessed, brand-level claim - a technician who passed an assessment
   * covering this exact device and declared this exact brand is much stronger
   * evidence than a self-typed skill tag, so it outranks `skill_tag`.
   */
  specialization: 0.32,
  /** Standard / pro / elite - a proxy for depth of experience. */
  tier: 0.10,
  /**
   * basic / verified / certified_pro. The secondary sort key after the
   * specialisation match.
   *
   * This REPLACED a boolean `verified` factor. Identity approval is now a hard
   * gate in Stage 1, so every candidate scored 1 on that boolean and it
   * carried no information at all - it spent 0.15 of the weight budget telling
   * the ranking nothing. The tier distinguishes candidates that the boolean
   * could not.
   */
  verification_tier: 0.14,
  /** Historical diagnosis accuracy on this exact device+symptom combo. */
  diagnosis_accuracy: 0.10,
  /**
   * What previous clients actually said about the work.
   *
   * Added because it was missing entirely: `technicians.rating` was printed on
   * every card and carried no weight in the ranking at all, so a 4.9 and a 3.1
   * were ordered identically. Client feedback is the only factor here measured
   * after the job rather than before it, which makes it the one piece of
   * evidence the technician cannot self-declare.
   *
   * The budget for it came from `tier` and `verification_tier`, which are both
   * proxies for the same thing - how good is this person - that rating
   * measures directly.
   *
   * Smoothed against a prior before it is used; see [RATING_PRIOR_WEIGHT].
   */
  rating: 0.12,
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
 * Verification tier maps to a 0..1 score.
 *
 * `basic` is not zero: identity was still approved by a human, which is the
 * hard requirement. The tier only says how much *extra* paperwork was checked,
 * so it should nudge a ranking rather than dominate it.
 */
export const VERIFICATION_TIER_SCORE: Record<string, number> = {
  basic: 0.55,
  verified: 0.80,
  certified_pro: 1.00,
};

/**
 * Stage 2 client-trust factor.
 *
 * Models how willing a technician is to commit to this client. A no-show costs
 * a technician a round trip across the city and an empty slot, so a client with
 * no history is a slightly worse bet than one with a record of turning up.
 *
 * SOFT, NEVER A BLOCK, and the floor is deliberately high. Every client starts
 * at `new`, so a harsh penalty here would make the platform unusable for
 * exactly the people it needs to attract - a cold-start trap on the client
 * side, mirroring the one `COLD_START_BOOST` solves for technicians. 0.70 is
 * a nudge between otherwise-equal candidates, not a barrier.
 */
export const CLIENT_TRUST_SCORE: Record<string, number> = {
  new: 0.70,
  verified: 0.90,
  trusted: 1.00,
};

/**
 * Extra penalty per recorded no-show, subtracted from the trust score.
 *
 * Capped by `MAX_NO_SHOW_PENALTY` so a client can never become unmatchable:
 * the platform's remedy for a repeat no-show is an account action, not a
 * silent inability to book anyone.
 */
export const NO_SHOW_PENALTY = 0.08;
export const MAX_NO_SHOW_PENALTY = 0.30;

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
// Stage 2 - Acceptance: will this technician actually take and complete it?
// ---------------------------------------------------------------------------

/** Must sum to 1.0. */
export const ACCEPTANCE_WEIGHTS = {
  /**
   * Can they be booked today? False only while they are on vacation.
   *
   * This was the online/offline switch until 2026-09-22, when the switch was
   * removed from the app and time off took its place (see
   * `availabilityScore`). The weight is unchanged.
   *
   * It is a score rather than a gate for the same reason an unverified
   * specialisation claim is: a technician who is the only expert on the
   * client's exact machine is worth showing with an "On vacation" label, so
   * the client understands why they cannot have them, rather than hiding them
   * so the Top 3 comes back empty.
   *
   * The heaviest factor in the stage. A technician on vacation loses all of
   * it - enough to sink them below any rival who can take the job, which is
   * right, since `job-response` will not let them be booked.
   */
  availability: 0.18,
  /** Does the client's budget cover this technician's tier rate? */
  budget_fit: 0.15,
  /** How booked are they right now? Also what spreads work around. */
  workload: 0.15,
  /** Home service when the client needs it today beats a shop pickup. */
  urgency_path: 0.11,
  /** Live congestion between technician and client, from TomTom. */
  traffic: 0.10,
  /**
   * Straight-line distance from their base, independent of current traffic.
   *
   * Raised from 0.08 when the service-radius hard gate became a penalty. While
   * anyone beyond their own radius was being deleted from the pool, distance
   * barely needed a weight - the gate had already done the work, and had also
   * been emptying the Top 3 entirely. Now that a distant technician stays in
   * the running, this is what keeps them *out of the top three* when a nearer
   * one is available, rather than out of the list.
   */
  proximity: 0.18,
  /** Live conditions at the job site, from OpenWeatherMap. */
  weather: 0.06,
  /**
   * How reliable the client is, from `client_verification_status`.
   *
   * The smallest weight in the stage, on purpose. It models a real cost to the
   * technician - a no-show is a wasted round trip - but it must never be the
   * reason a new client cannot get matched.
   */
  client_trust: 0.07,
} as const;

/**
 * How exposed each service path is to travel conditions.
 *
 * A home service is fully exposed: the technician rides through the rain and
 * the traffic to reach the client. A pickup is partly exposed - one trip, at a
 * time of their choosing. An IT community job is remote, so weather and
 * traffic are nearly irrelevant. Multiplying the raw penalty by this factor is
 * what stops a rainy afternoon from flattening every score equally.
 */
export const TRAVEL_EXPOSURE: Record<string, number> = {
  home_service: 1.00,
  pickup: 0.60,
  it_community: 0.10,
};

/**
 * Urgency x path fit.
 *
 * The brief: boost home service over pickup when urgency is high. When the
 * client can wait, path choice barely predicts acceptance, so the scores sit
 * close together and other factors decide.
 */
export const URGENCY_PATH_SCORE: Record<string, Record<string, number>> = {
  need_today: {
    home_service: 1.00,
    pickup: 0.55,
    it_community: 0.40,
  },
  can_wait: {
    home_service: 0.85,
    pickup: 0.85,
    it_community: 0.75,
  },
};

/** Workload at or above this is treated as fully booked (score 0). */
export const MAX_WORKLOAD = 5;

/** Beyond this radius a technician is dropped from the pool entirely. */
export const HARD_RADIUS_KM = 50;

/** Distance at which the proximity factor reaches 0. Inside it, linear. */
export const SOFT_RADIUS_KM = 25;

/** Indicative hourly rate per tier, in PHP. Mirrors `Technician._tierRates`. */
export const TIER_HOURLY_RATE: Record<string, number> = {
  standard: 350,
  pro: 550,
  elite: 800,
};

/** Billable hours in a typical repair, used to turn a rate into a job cost. */
export const TYPICAL_JOB_HOURS = 3;

/** Score used when the client gave no budget - neutral, neither help nor harm. */
export const NEUTRAL_BUDGET_FIT = 0.70;

/**
 * How far over budget a quote can run before budget fit hits 0. At 2.0 a quote
 * of exactly twice the client's ceiling scores 0, and everything between the
 * ceiling and that point degrades linearly.
 */
export const BUDGET_OVERRUN_TOLERANCE = 2.0;

// ---------------------------------------------------------------------------
// Stage 3 - Recommendation: which qualified technicians fit THIS client, now?
// ---------------------------------------------------------------------------

/**
 * The recommendation score, and the ranking, is a weighted mean of these.
 * Must sum to 1.0.
 *
 * It replaced `FINAL_WEIGHTS` (suitability 0.60, acceptance 0.40) on
 * 2026-09-27, when the brief split *matching* ("who is qualified and
 * compatible?") from *recommendation* ("who is most relevant to this client in
 * this situation?"). The two stage scores are still its two biggest inputs.
 *
 * Suitability stays the heaviest, by a wide margin, for the reason the old
 * weights gave: a technician who is close, free and cheap but cannot fix the
 * device is a worse outcome than a slightly slower one who can. With no client
 * history (`client_preference` dropped, weight redistributed) it carries half
 * the score.
 */
export const RECOMMENDATION_WEIGHTS = {
  /** Stage 1, whole. Can they do this repair well? */
  suitability: 0.45,
  /** Stage 2, whole. Are they likely to accept it? */
  acceptance: 0.20,
  /**
   * Do they fit the conditions right now - urgency, rain, traffic, their own
   * service area? Overlaps Stage 2 on purpose: the matching rules raise this
   * weight exactly when conditions are unusual, which is when fit to them
   * should decide more.
   */
  context_fit: 0.15,
  /**
   * This client's own history with this technician. Null for a client with no
   * past bookings, and then dropped - a new user has no preferences, and we do
   * not invent any.
   */
  client_preference: 0.10,
  /** Track record beyond Stage 1: do they answer offers, how much have they done? */
  technician_performance: 0.10,
} as const;

/**
 * Client preference, from this client's past jobs and the stars they gave.
 *
 * "Not yet" is the middle, not zero: never having booked someone is not a mark
 * against them. A poor past rating is the only value near the floor - the
 * client has told us directly they did not want this person again.
 */
export const CLIENT_PREFERENCE_SCORE = {
  /** They rated this technician WELL_RATED_STARS or more before. */
  rated_well: 1.00,
  /** They had a job with this technician before and did not rate it. */
  worked_before: 0.75,
  /** The client has history, just none with this technician. */
  not_yet: 0.50,
  /** They rated this technician POORLY_RATED_STARS or fewer before. */
  rated_poorly: 0.10,
} as const;

export const WELL_RATED_STARS = 4;
export const POORLY_RATED_STARS = 2;

/**
 * Response behaviour: how often a technician accepts the offers they are sent.
 *
 * Smoothed toward a prior exactly like diagnosis accuracy, and for the same
 * reason - one decline from a newcomer is not a 0% response rate. With a
 * weight of 3, it takes about three answered offers before their own record
 * outweighs the prior.
 */
export const RESPONSE_PRIOR = 0.75;
export const RESPONSE_PRIOR_WEIGHT = 3;

/**
 * Experience, on a log scale that reaches 1.0 at this many completed jobs.
 * Logarithmic because 2 jobs versus 20 is a real difference and 200 versus 220
 * is noise - the same shape `recommended_technicians` uses.
 */
export const EXPERIENCE_SATURATION_JOBS = 50;

/** Travel time at which the context-fit travel component reaches 0. */
export const ETA_FIT_MINUTES = 60;

/** Outside their declared service area: context fit for that component. */
export const OUTSIDE_SERVICE_AREA_FIT = 0.30;

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
 * No factor's weight can be multiplied by more than this, however many rules
 * fire. Without a cap, three rules that each boost proximity would compound
 * into a ranking that is about distance and nothing else.
 */
export const MAX_RULE_MULTIPLIER = 2.0;

/** How many offers we write to `job_matches`. The check constraint allows 1-3. */
export const TOP_N = 3;

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
assertWeightsSumToOne("RECOMMENDATION_WEIGHTS", RECOMMENDATION_WEIGHTS);
