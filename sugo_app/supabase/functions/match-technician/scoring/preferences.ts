/**
 * Client preference pre-filter (2026-11-15).
 *
 * The client may set MINIMUM requirements for their technician while posting:
 * a specialisation, a maximum distance, a minimum rating, an availability
 * window and a minimum trust badge. This module turns those into hard gates.
 *
 * ## Where it sits in the pipeline
 *
 *   1. Stage 1 hard gates (existing) - verified, identity approved, not already
 *      declined, inside the 50 km ceiling
 *   2. Client preference pre-filter (THIS) - removes whoever fails a
 *      requirement the client set
 *   3. Context detection + weighted scoring (Stage 1, rules re-weight it)
 *   4. Acceptance likelihood (Stage 2, Table 11)
 *   5. Final score (Table 10) and the Top 3
 *
 * ## The rules this module keeps
 *
 * * **Gates, not weights.** A technician who fails a preference is removed,
 *   never ranked lower. The weight tables, the composite formula and Stage 2
 *   are not touched, and nothing here returns a number that feeds a score.
 * * **Null filters nobody.** Every preference is optional. A job that sets
 *   none gets back exactly the list it was given, so its ranking is identical
 *   to before this feature existed.
 * * **Rule-based.** Each check is an explicit `if` on a column the engine
 *   already reads. No model, no learned threshold.
 * * **Pure.** No database, no network. The two facts that need a query (who
 *   is busy, who is away on a date) are loaded by `engine.ts` and passed in,
 *   which is what lets `preferences.test.ts` pin every rule under plain Node.
 */
import type {
  JobRow,
  PreferredSpecialization,
  TechnicianRow,
  TrustRequirement,
} from "./types.ts";

/** One preference the client can set. Also the key the app reads hints by. */
export type PreferenceKey =
  | "specialization"
  | "max_distance_km"
  | "min_rating"
  | "availability"
  | "min_trust";

/** The client's preferences, read off the job and validated. */
export interface ClientPreferences {
  specialization: PreferredSpecialization | null;
  maxDistanceKm: number | null;
  minRating: number | null;
  availability: "now" | "on_date" | null;
  /** `YYYY-MM-DD`; only meaningful with `availability = 'on_date'`. */
  availableOn: string | null;
  minTrust: TrustRequirement | null;
}

/**
 * The facts a preference needs that are not on the candidate row.
 *
 * Loaded by the engine only when the matching preference is set, so a job
 * with no availability preference costs no extra query.
 */
export interface AvailabilityFacts {
  /** On another unfinished job right now (`confirmed` / `in_progress`). */
  busy: Set<string>;
  /** Time off covering `availableOn`. */
  awayOnDate: Set<string>;
}

export const NO_AVAILABILITY_FACTS: AvailabilityFacts = {
  busy: new Set(),
  awayOnDate: new Set(),
};

// ------------------------------------------------------------ fixed options
//
// The same lists the database CHECK constraints allow. Anything else read off
// a row is ignored rather than trusted - a value the app cannot have written
// must not be able to empty a client's Top 3.

const DISTANCE_OPTIONS_KM = [3, 5, 10] as const;
const RATING_OPTIONS = [3.0, 4.0, 4.5] as const;

/**
 * Which `technician_specializations.device_type` values count as offering
 * each specialisation. Declared counts - "offers" is what the technician says
 * they do. Whether SUGO has *checked* it is the trust ladder's question.
 */
export const SPECIALIZATION_DEVICES: Record<PreferredSpecialization, string[]> = {
  computer: ["laptop", "desktop"],
  phone_tablet: ["smartphone", "tablet"],
  network_setup: ["router", "cctv", "printer"],
  appliance: ["aircon", "refrigerator", "washing_machine", "television", "microwave"],
  pc_building: ["desktop"],
};

/**
 * The coarse value an account that predates registration carries in the
 * legacy `technicians.specialization` text[] - the same fallback Stage 1's
 * ladder honours. PC building has none: "laptop" there cannot say whether
 * they build desktops, and guessing yes would let anyone through.
 */
const LEGACY_SPECIALIZATION: Record<PreferredSpecialization, string | null> = {
  computer: "laptop",
  phone_tablet: "phone",
  network_setup: "network",
  appliance: "appliance",
  pc_building: null,
};

/**
 * The Progressive Trust Badge, in order (20261115000002). A requirement is
 * met by its own rung or any rung above it - "Skill verified" keeps Community
 * Trusted technicians too. Compared with `>=`, never equality.
 */
export const TRUST_LADDER: Record<TrustRequirement, number> = {
  id_verified: 1,
  skill_verified: 2,
  community_trusted: 3,
};

/** Rung back to its name; index 0 is "below the baseline". */
const TRUST_NAMES: (TrustRequirement | null)[] = [
  null,
  "id_verified",
  "skill_verified",
  "community_trusted",
];

/** Client-facing labels, used in the explanation when nobody qualifies. */
const SPECIALIZATION_LABEL: Record<PreferredSpecialization, string> = {
  computer: "Computer/Laptop",
  phone_tablet: "Phone/Tablet",
  network_setup: "Network & Device Setup",
  appliance: "Appliance Service",
  pc_building: "PC Building",
};

const TRUST_LABEL: Record<TrustRequirement, string> = {
  id_verified: "ID verified",
  skill_verified: "Skill verified",
  community_trusted: "Community Trusted",
};

// ---------------------------------------------------------------- reading

/**
 * Reads the six `pref_*` columns into one validated object.
 *
 * `numeric` columns can arrive as strings from PostgREST, so the rating is
 * coerced; anything outside the fixed options becomes null ("No preference").
 * A date preference without a date is dropped the same way - it cannot be
 * checked, and an unverifiable gate must not silently remove everyone.
 */
export function readPreferences(job: JobRow): ClientPreferences {
  // `Object.hasOwn`, not `in`: `"toString" in {}` is true.
  const specialization = job.pref_specialization &&
      Object.hasOwn(SPECIALIZATION_DEVICES, job.pref_specialization)
    ? job.pref_specialization
    : null;

  const distance = Number(job.pref_max_distance_km);
  const maxDistanceKm = (DISTANCE_OPTIONS_KM as readonly number[]).includes(distance)
    ? distance
    : null;

  const rating = Number(job.pref_min_rating);
  const minRating = (RATING_OPTIONS as readonly number[]).includes(rating) ? rating : null;

  const availableOn = typeof job.pref_available_on === "string" &&
      /^\d{4}-\d{2}-\d{2}/.test(job.pref_available_on)
    ? job.pref_available_on.slice(0, 10)
    : null;

  let availability: ClientPreferences["availability"] = null;
  if (job.pref_availability === "now") availability = "now";
  if (job.pref_availability === "on_date" && availableOn) availability = "on_date";

  const minTrust = job.pref_min_trust && Object.hasOwn(TRUST_LADDER, job.pref_min_trust)
    ? job.pref_min_trust
    : null;

  return {
    specialization,
    maxDistanceKm,
    minRating,
    availability,
    availableOn: availability === "on_date" ? availableOn : null,
    minTrust,
  };
}

/** The preferences the client actually set, in the order the app shows them. */
export function activePreferences(prefs: ClientPreferences): PreferenceKey[] {
  const keys: PreferenceKey[] = [];
  if (prefs.specialization) keys.push("specialization");
  if (prefs.maxDistanceKm !== null) keys.push("max_distance_km");
  if (prefs.minRating !== null) keys.push("min_rating");
  if (prefs.availability) keys.push("availability");
  if (prefs.minTrust) keys.push("min_trust");
  return keys;
}

// ------------------------------------------------------------ single checks

/** Whether the technician declared anything under this specialisation. */
export function offersSpecialization(
  technician: TechnicianRow,
  specialization: PreferredSpecialization,
): boolean {
  const devices = SPECIALIZATION_DEVICES[specialization];
  if ((technician.specializations ?? []).some((s) => devices.includes(s.device_type))) {
    return true;
  }
  const legacy = LEGACY_SPECIALIZATION[specialization];
  return legacy !== null && (technician.specialization ?? []).includes(legacy);
}

/**
 * The technician's rung on the trust ladder, for THIS job.
 *
 *   0  below the baseline (no badge)
 *   1  ID verified
 *   2  Skill verified - for a device this job needs
 *   3  Community Trusted - and skill verified for this job's device
 *
 * Starts from the account-wide badge `evaluate_technician_badge()` stored -
 * the one source of truth - and caps it at ID verified when none of the
 * technician's VERIFIED specialisations covers this job's device. That is
 * the brief's "Skill Verified only for Phone/Tablet is not matched for PC
 * Building jobs": for that job they hold rung 1, so a client who requires
 * Skill verified or higher does not get them, and Stage 1's trust factor
 * scores them at the ID level. (A universal hard gate was considered and
 * rejected with the user: it would empty Top 3s while few technicians have
 * passed assessments.)
 *
 * Rung 3 requires rung 2 for this job, so the ladder stays ordered: a
 * Community Trusted technician never assessed on this device does not
 * outrank a skill-verified one.
 */
export function trustRungOf(
  technician: TechnicianRow,
  deviceCandidates: string[],
): number {
  const stored = technician.badge && Object.hasOwn(TRUST_LADDER, technician.badge)
    ? TRUST_LADDER[technician.badge as TrustRequirement]
    : 0;
  if (stored === 0) return 0;

  const skillVerifiedForJob = (technician.specializations ?? []).some((s) =>
    s.verified && deviceCandidates.includes(s.device_type)
  );
  return skillVerifiedForJob ? stored : Math.min(stored, 1);
}

/** `trustRungOf` as the badge name, for the match card. */
export function trustBadgeForJob(
  technician: TechnicianRow,
  deviceCandidates: string[],
): TrustRequirement | null {
  return TRUST_NAMES[trustRungOf(technician, deviceCandidates)] ?? null;
}

/**
 * Every preference this technician fails. Empty means they stay.
 *
 * One explicit `if` per preference, each skipped when the client did not set
 * it. A missing fact fails a set preference rather than passing it: a
 * technician with no base location cannot be shown to be within 5 km, so a
 * client who asked for 5 km does not get them.
 */
export function failedPreferences(
  technician: TechnicianRow,
  distanceKm: number | null,
  prefs: ClientPreferences,
  deviceCandidates: string[],
  facts: AvailabilityFacts,
): PreferenceKey[] {
  const failed: PreferenceKey[] = [];

  if (prefs.specialization && !offersSpecialization(technician, prefs.specialization)) {
    failed.push("specialization");
  }

  if (prefs.maxDistanceKm !== null &&
      (distanceKm === null || distanceKm > prefs.maxDistanceKm)) {
    failed.push("max_distance_km");
  }

  // A technician with no reviews has rating 0 and fails any minimum. The app
  // says so beside the field, because it is the one surprising consequence.
  if (prefs.minRating !== null && Number(technician.rating ?? 0) < prefs.minRating) {
    failed.push("min_rating");
  }

  if (prefs.availability === "now" &&
      (technician.away_until || facts.busy.has(technician.id))) {
    failed.push("availability");
  }
  if (prefs.availability === "on_date" && facts.awayOnDate.has(technician.id)) {
    failed.push("availability");
  }

  if (prefs.minTrust &&
      trustRungOf(technician, deviceCandidates) < TRUST_LADDER[prefs.minTrust]) {
    failed.push("min_trust");
  }

  return failed;
}

// ------------------------------------------------------------ the filter

/** "Remove this one preference and N technicians would qualify." */
export interface RelaxHint {
  preference: PreferenceKey;
  would_match: number;
}

export interface PreferenceFilterResult {
  /** Candidates who meet every preference, in their original order. */
  kept: TechnicianRow[];
  /** The preferences that were set. Empty = the filter did nothing. */
  active: PreferenceKey[];
  /** How many candidates came in. */
  before: number;
  /** How many fail each preference, counted independently. */
  failing: Partial<Record<PreferenceKey, number>>;
  /**
   * Only when nobody is kept: for each preference, how many would qualify if
   * the client removed just that one. The app puts the number on the chip,
   * so "try relaxing them" says which one to relax.
   */
  relaxHints: RelaxHint[];
}

/**
 * Runs AFTER the Stage 1 hard gates and BEFORE context scoring.
 *
 * Returns the narrowed list and enough about it to explain an empty result.
 * With no preference set it returns the candidates untouched - the same array
 * contents, the same order - which is the "no preference => identical ranking"
 * guarantee.
 */
export function applyClientPreferenceFilter(
  candidates: TechnicianRow[],
  distances: Map<string, number | null>,
  prefs: ClientPreferences,
  deviceCandidates: string[],
  facts: AvailabilityFacts = NO_AVAILABILITY_FACTS,
): PreferenceFilterResult {
  const active = activePreferences(prefs);

  if (active.length === 0) {
    return {
      kept: candidates,
      active,
      before: candidates.length,
      failing: {},
      relaxHints: [],
    };
  }

  const kept: TechnicianRow[] = [];
  const failing: Partial<Record<PreferenceKey, number>> = {};
  const failedBy: PreferenceKey[][] = [];

  for (const technician of candidates) {
    const failed = failedPreferences(
      technician,
      distances.get(technician.id) ?? null,
      prefs,
      deviceCandidates,
      facts,
    );
    failedBy.push(failed);
    if (failed.length === 0) kept.push(technician);
    for (const key of failed) failing[key] = (failing[key] ?? 0) + 1;
  }

  // A technician comes back when one preference is removed exactly when that
  // preference is the only one they fail.
  const relaxHints: RelaxHint[] = kept.length > 0 ? [] : active.map((preference) => ({
    preference,
    would_match: failedBy.filter((failed) =>
      failed.length === 1 && failed[0] === preference
    ).length,
  }));

  return { kept, active, before: candidates.length, failing, relaxHints };
}

// ------------------------------------------------------- distance fallback

/**
 * What the engine did when nobody was within the client's distance limit
 * (2026-11-17). Written into each match's `score_breakdown` as
 * `preference_fallback`, so the app can say so on every visit, not only on
 * the run that produced it.
 */
export interface DistanceFallback {
  /** The limit the client set, e.g. 5. */
  wanted_km: number;
  /** The nearest technician who meets everything else, e.g. 12.4. */
  nearest_km: number | null;
}

/**
 * The one preference that is softened rather than enforced to the letter.
 *
 * At the user's request: a client who asked for "within 5 km" when the nearest
 * qualified technician is 12 km away is shown those technicians, with
 * "no technician within 5 km - the nearest is 12 km away", instead of an empty
 * screen. Only when the distance limit is the thing standing in the way:
 * every OTHER preference still holds, so the fallback list is exactly the
 * technicians who fail on distance alone.
 *
 * Returns null when the fallback does not apply - something was kept, no
 * distance limit was set, or removing it would bring back nobody.
 */
export function distanceFallback(
  result: PreferenceFilterResult,
  candidates: TechnicianRow[],
  distances: Map<string, number | null>,
  prefs: ClientPreferences,
  deviceCandidates: string[],
  facts: AvailabilityFacts = NO_AVAILABILITY_FACTS,
): { kept: TechnicianRow[]; fallback: DistanceFallback } | null {
  if (result.kept.length > 0 || prefs.maxDistanceKm === null) return null;
  const hint = result.relaxHints.find((h) => h.preference === "max_distance_km");
  if (!hint || hint.would_match === 0) return null;

  const relaxed = applyClientPreferenceFilter(
    candidates,
    distances,
    { ...prefs, maxDistanceKm: null },
    deviceCandidates,
    facts,
  );
  if (relaxed.kept.length === 0) return null;

  const known = relaxed.kept
    .map((t) => distances.get(t.id))
    .filter((d): d is number => typeof d === "number");
  return {
    kept: relaxed.kept,
    fallback: {
      wanted_km: prefs.maxDistanceKm,
      nearest_km: known.length === 0
        ? null
        : Math.round(Math.min(...known) * 10) / 10,
    },
  };
}

/** "No technician within 5 km - the nearest is 12.4 km away." */
export function distanceFallbackMessage(fallback: DistanceFallback): string {
  const head = `No technician within ${fallback.wanted_km} km`;
  return fallback.nearest_km === null
    ? `${head}. Showing the closest who meet your other preferences.`
    : `${head} - the nearest is ${fallback.nearest_km} km away.`;
}

// ------------------------------------------------------------ explanation

/** A preference as the client chose it, e.g. "Within 5 km". */
export function preferenceLabel(key: PreferenceKey, prefs: ClientPreferences): string {
  switch (key) {
    case "specialization":
      return prefs.specialization
        ? `${SPECIALIZATION_LABEL[prefs.specialization]} specialist`
        : "Specialisation";
    case "max_distance_km":
      return `Within ${prefs.maxDistanceKm} km`;
    case "min_rating":
      return `${prefs.minRating?.toFixed(1)}+ rating`;
    case "availability":
      return prefs.availability === "on_date" && prefs.availableOn
        ? `Available on ${prefs.availableOn}`
        : "Available now";
    case "min_trust":
      return prefs.minTrust ? `${TRUST_LABEL[prefs.minTrust]} or higher` : "Trust badge";
  }
}

/**
 * The sentence the client reads when their preferences left nobody.
 *
 * Names the single preference whose removal brings back the most technicians,
 * because "try relaxing them" alone leaves the client guessing which one.
 */
export function relaxMessage(
  result: PreferenceFilterResult,
  prefs: ClientPreferences,
): string {
  const checked = `${result.before} technician${result.before === 1 ? "" : "s"} checked`;
  const head = `No technician matches all of your preferences (${checked}).`;

  const best = [...result.relaxHints].sort((a, b) => b.would_match - a.would_match)[0];
  if (!best || best.would_match === 0) {
    return `${head} Try relaxing more than one of them.`;
  }

  const count = best.would_match;
  return `${head} Removing “${preferenceLabel(best.preference, prefs)}” would ` +
    `bring back ${count} technician${count === 1 ? "" : "s"}.`;
}
