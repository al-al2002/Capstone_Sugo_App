/**
 * Stage 1 - Suitability.
 *
 * "Can this technician fix this device, for this symptom, well?"
 *
 * Nothing in this stage depends on the outside world: no traffic, no weather,
 * no distance. It is a pure function of the job, the technician's record and
 * the feedback history. That separation is deliberate - it means Stage 1 is
 * reproducible and testable, and any two runs on the same data give the same
 * answer. Stage 2 owns everything that changes minute to minute.
 */
import {
  ACCURACY_PRIOR,
  COLD_START_BOOST,
  COLD_START_MAX_JOBS,
  RATING_MAX,
  RATING_MIN,
  RATING_PRIOR_MEAN,
  RATING_PRIOR_WEIGHT,
  SPECIALIZATION_MATCH,
  SUITABILITY_WEIGHTS,
  TIER_SCORE,
  VERIFICATION_TIER_SCORE,
} from "./constants.ts";
import { clamp01 } from "./geo.ts";
import { combine, round, type FactorInput } from "./weighting.ts";
import type {
  AccuracyStats,
  JobContext,
  JobRow,
  SpecializationRow,
  StageResult,
  TechnicianRow,
} from "./types.ts";

/** Splits a code like `laptop_screen_broken` into comparable tokens. */
function tokenize(value: string): string[] {
  return value
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length > 1);
}

/**
 * How well the technician's `skill_tags` cover this job's symptom.
 *
 * Three tiers of evidence, strongest first:
 *
 * 1. A tag equal to the symptom code, e.g. `laptop_screen_broken`. Direct hit.
 * 2. A tag sharing tokens with the symptom, e.g. `screen_replacement` against
 *    `laptop_screen_broken`. Scored by the share of symptom tokens covered.
 * 3. A tag naming only the device, e.g. `laptop`. Generic competence.
 */
export function skillTagScore(
  job: JobRow,
  technician: TechnicianRow,
): { value: number; note: string } {
  const tags = technician.skill_tags ?? [];
  if (tags.length === 0) {
    return { value: 0.1, note: "No skill tags listed yet" };
  }

  const symptom = job.problem_symptom.toLowerCase();

  if (tags.some((tag) => tag.toLowerCase() === symptom)) {
    return { value: 1, note: `Lists ${job.problem_symptom} as a skill` };
  }

  const symptomTokens = tokenize(symptom);
  let best = 0;
  let bestTag = "";

  for (const tag of tags) {
    const tagTokens = tokenize(tag);
    if (tagTokens.length === 0) continue;

    // Share of the symptom's own tokens this tag covers.
    const shared = symptomTokens.filter((token) => tagTokens.includes(token));
    if (shared.length === 0) continue;

    const coverage = shared.length / symptomTokens.length;
    // A tag naming only the device is weaker evidence than one naming the part.
    const deviceOnly = shared.length === 1 && shared[0] === job.device_type;
    const value = deviceOnly ? 0.4 : clamp01(0.35 + coverage * 0.55);

    if (value > best) {
      best = value;
      bestTag = tag;
    }
  }

  if (best === 0) {
    return { value: 0, note: "No skill tag covers this symptom" };
  }
  return { value: best, note: `Related skill: ${bestTag}` };
}

/** A brand the client did not really specify. */
function brandIsUnspecified(brand: string | null): boolean {
  if (brand === null) return true;
  const value = brand.trim().toLowerCase();
  return value === "" || value === "others" || value === "other" ||
    value === "unknown";
}

/**
 * Stage 1 specialisation match - the brand + device ladder.
 *
 * ## Priority order
 *
 *   (a) Assessed Expert on this exact brand AND device      1.00
 *   (b) Assessed Intermediate on this exact brand AND device 0.85
 *   (c) Assessed on the device, different brand              0.70 / 0.60
 *   (d) Declared but never assessed, brand or device         0.35
 *       Legacy `technicians.specialization` array only       0.30
 *       No match at all                                      0.10
 *
 * ## Why (d) is included rather than filtered out
 *
 * A self-claimed specialisation is weak evidence, not disqualifying evidence.
 * Excluding it would mean a client whose brand nobody has been assessed on
 * gets fewer than three options - and the Top 3 is the product. It ranks last
 * instead.
 *
 * ## Why the brand filter is skipped for "Others"
 *
 * If the client picked "Others" or left the brand blank, insisting on a brand
 * match would exclude every technician on a technicality the client never
 * expressed. In that case the ladder degrades to device-only, which is exactly
 * what the brief asks for.
 *
 * ## Which device values are compared
 *
 * `context.deviceCandidates` comes from `job_device_candidates()`, which
 * bridges the coarse `jobs.device_type` vocabulary (laptop/phone/appliance/
 * network) and the fine `technician_specializations.device_type` one. A direct
 * equality test between the two would match only the literal word "laptop" and
 * would silently exclude every desktop, aircon and washing-machine technician
 * on the platform.
 */
export function specializationMatchScore(
  job: JobRow,
  technician: TechnicianRow,
  context: JobContext,
): { value: number; note: string; matched: string[] } {
  const specializations = technician.specializations ?? [];
  const devices = context.deviceCandidates;
  const skipBrand = brandIsUnspecified(job.brand);
  const wantedBrand = (job.brand ?? "").trim().toLowerCase();

  // Rows that cover a device this job could need.
  const onDevice = specializations.filter((s: SpecializationRow) =>
    devices.includes(s.device_type)
  );

  const onBrand = skipBrand ? [] : onDevice.filter((s: SpecializationRow) =>
    s.brand.trim().toLowerCase() === wantedBrand
  );

  const label = (rows: SpecializationRow[]) =>
    rows.map((s) => `${s.device_type}/${s.brand}`);

  // ------------------------------------------------- (a) and (b): exact brand
  const brandExpert = onBrand.find((s) => s.verified && s.skill_level === "expert");
  if (brandExpert) {
    return {
      value: SPECIALIZATION_MATCH.expert_brand,
      note: `Assessed Expert on ${brandExpert.brand} ${brandExpert.device_type}`,
      matched: label(onBrand),
    };
  }

  const brandIntermediate = onBrand.find(
    (s) => s.verified && s.skill_level === "intermediate",
  );
  if (brandIntermediate) {
    return {
      value: SPECIALIZATION_MATCH.intermediate_brand,
      note:
        `Assessed Intermediate on ${brandIntermediate.brand} ` +
        `${brandIntermediate.device_type}`,
      matched: label(onBrand),
    };
  }

  // ------------------------------------ (c) assessed on the device, any brand
  const deviceExpert = onDevice.find((s) => s.verified && s.skill_level === "expert");
  if (deviceExpert) {
    return {
      value: SPECIALIZATION_MATCH.expert_device,
      note: skipBrand
        ? `Assessed Expert on ${deviceExpert.device_type}`
        : `Assessed Expert on ${deviceExpert.device_type}, though not on ` +
          `${job.brand} specifically`,
      matched: label(onDevice),
    };
  }

  const deviceIntermediate = onDevice.find(
    (s) => s.verified && s.skill_level === "intermediate",
  );
  if (deviceIntermediate) {
    return {
      value: SPECIALIZATION_MATCH.intermediate_device,
      note: `Assessed Intermediate on ${deviceIntermediate.device_type}`,
      matched: label(onDevice),
    };
  }

  // --------------------------------- (d) declared, never assessed. Still in.
  if (onBrand.length > 0 || onDevice.length > 0) {
    const rows = onBrand.length > 0 ? onBrand : onDevice;
    return {
      value: SPECIALIZATION_MATCH.unverified_claim,
      note: `Lists ${label(rows)[0]} but has not passed its assessment`,
      matched: label(rows),
    };
  }

  // Accounts that predate registration have only the legacy text[] column.
  const legacy = technician.specialization ?? [];
  if (legacy.includes(job.device_type)) {
    return {
      value: SPECIALIZATION_MATCH.legacy_array,
      note: `Lists ${job.device_type} on an older profile`,
      matched: [],
    };
  }

  return {
    value: SPECIALIZATION_MATCH.none,
    note: legacy.length > 0
      ? `Specialises in ${legacy.join(", ")}, not ${job.device_type}`
      : "No declared specialisation covers this device",
    matched: [],
  };
}

/**
 * Runs Stage 1 for one technician.
 *
 * Returns the stage result plus the cold-start boost applied, so the caller can
 * surface "newly verified technician" in the explainability line.
 */
/**
 * What previous clients said, smoothed so a thin history cannot dominate.
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

export function scoreSuitability(
  job: JobRow,
  technician: TechnicianRow,
  accuracy: AccuracyStats,
  context: JobContext,
): {
  stage: StageResult;
  coldStartApplied: boolean;
  matchedSpecializations: string[];
} {
  const skill = skillTagScore(job, technician);
  const specialization = specializationMatchScore(job, technician, context);

  const totalJobs = technician.total_jobs ?? 0;
  const isColdStart = technician.is_verified &&
    totalJobs <= COLD_START_MAX_JOBS;

  const accuracyNote = accuracy.similarRepairs > 0
    ? `${accuracy.similarRepairs} similar repair${
      accuracy.similarRepairs === 1 ? "" : "s"
    }, ${Math.round(accuracy.signal * 100)}% diagnosed correctly`
    : isColdStart
    ? "No history yet, scored at the neutral prior"
    : `No ${job.device_type} history for this symptom`;

  const rating = ratingScore(technician);

  const inputs: FactorInput[] = [
    {
      key: "skill_tag",
      label: "Skill match",
      value: skill.value,
      weight: SUITABILITY_WEIGHTS.skill_tag,
      note: skill.note,
    },
    {
      // The brand + device ladder. The heaviest factor in Stage 1, because an
      // assessed brand-level claim is the strongest evidence the platform has
      // that this person can fix this exact machine.
      key: "specialization",
      label: "Brand and device match",
      value: specialization.value,
      weight: SUITABILITY_WEIGHTS.specialization,
      note: specialization.note,
    },
    {
      key: "tier",
      label: "Tier",
      value: TIER_SCORE[technician.tier] ?? TIER_SCORE.standard,
      weight: SUITABILITY_WEIGHTS.tier,
      note: `${technician.tier} tier technician`,
    },
    {
      // Secondary sort key after the specialisation match.
      //
      // This replaced a boolean `verified` factor. Identity approval is now a
      // hard gate in the engine, so that boolean was 1 for every candidate
      // that reached this point - it spent weight telling the ranking nothing.
      // The tier says how much SUGO actually checked, which does differ
      // between candidates.
      key: "verification_tier",
      label: "Verification tier",
      value: VERIFICATION_TIER_SCORE[technician.verification_tier ?? "basic"] ??
        VERIFICATION_TIER_SCORE.basic,
      weight: SUITABILITY_WEIGHTS.verification_tier,
      note: technician.verification_tier === "certified_pro"
        ? "Certified Pro: ID, assessment and approved credentials on file"
        : technician.verification_tier === "verified"
        ? "Verified: ID approved and assessment passed"
        : "Basic: ID approved",
    },
    {
      key: "diagnosis_accuracy",
      label: "Diagnosis accuracy",
      // Never null: with no evidence this is ACCURACY_PRIOR, so a newcomer is
      // treated as unknown rather than incompetent.
      value: accuracy.signal,
      weight: SUITABILITY_WEIGHTS.diagnosis_accuracy,
      note: accuracyNote,
    },
    {
      key: "rating",
      label: "Client rating",
      value: rating.value,
      weight: SUITABILITY_WEIGHTS.rating,
      note: rating.note,
    },
  ];

  const stage = combine(inputs);

  if (!isColdStart) {
    return {
      stage,
      coldStartApplied: false,
      matchedSpecializations: specialization.matched,
    };
  }

  // Cold start: a verified newcomer with zero completed jobs gets a bounded
  // lift so they can appear in a Top 3 and earn their first real data point.
  // The boost cannot push anyone past 1.0, and it stops applying the moment
  // total_jobs reaches 1.
  const boosted = round(clamp01(stage.score + COLD_START_BOOST));

  return {
    stage: {
      score: boosted,
      factors: [
        ...stage.factors,
        {
          key: "cold_start",
          label: "New technician boost",
          value: 1,
          weight: round(COLD_START_BOOST),
          contribution: round(boosted - stage.score),
          note:
            `Verified with no completed jobs yet: +${COLD_START_BOOST} so a ` +
            `newcomer is not locked out by an empty history ` +
            `(accuracy scored at the ${ACCURACY_PRIOR} prior)`,
        },
      ],
    },
    coldStartApplied: true,
    matchedSpecializations: specialization.matched,
  };
}
