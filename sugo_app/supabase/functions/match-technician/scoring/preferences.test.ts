/**
 * The client preference pre-filter, pinned to the brief's acceptance criteria.
 *
 * A gate that is wrong does not throw - it silently hands a client a Top 3
 * that ignores what they asked for, or an empty one they did not deserve.
 * Every rule in `preferences.ts` is therefore checked here, including the
 * guarantee that a job with no preferences is passed through untouched.
 *
 * Run with Node's TypeScript stripping (no Deno needed):
 *
 *   cd supabase/functions/match-technician/scoring
 *   node --experimental-strip-types preferences.test.ts
 */
import {
  applyClientPreferenceFilter,
  distanceFallback,
  distanceFallbackMessage,
  readPreferences,
  relaxMessage,
  trustRungOf,
} from "./preferences.ts";

// ------------------------------------------------------------------ fixtures

const job = (prefs: Record<string, unknown> = {}) => ({
  id: "j", client_id: "c", device_type: "phone", problem_symptom: "screen",
  has_physical_damage: false, classification_confidence: null, service_path: null,
  urgency: "can_wait", latitude: 7.07, longitude: 125.61, budget_min: null,
  budget_max: null, preferred_schedule: null, description: null, photo_urls: null,
  status: "pending", assigned_technician_id: null, brand: null, device_detail: null,
  ...prefs,
}) as any;

const spec = (device: string, verified = false) =>
  ({ device_type: device, brand: "Others", skill_level: verified ? "expert" : null, verified, track: null });

const tech = (id: string, over: Record<string, unknown> = {}) => ({
  id, skill_tags: [], tier: "standard", specialization: [], is_verified: true,
  badge: null, rating: 4.8, total_jobs: 10, current_workload: 0,
  latitude: null, longitude: null, base_latitude: 7.07, base_longitude: 125.61,
  service_radius_km: 10, verification_tier: "verified", identity_approved: true,
  specializations: [spec("smartphone", true)], created_at: null, away_until: null,
  // The stored Progressive Trust Badge (20261115000002).
  badge: "skill_verified",
  ...over,
}) as any;

const PHONE_DEVICES = ["smartphone", "tablet"];

let failures = 0;
function check(name: string, ok: boolean, detail = "") {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(60)} ${ok ? "" : detail}`);
}
const ids = (rows: { id: string }[]) => rows.map((r) => r.id).join(",");

// A small, deliberately mixed pool. Distances are supplied directly - the
// filter takes the engine's distance map, it does not compute geography.
const pool = [
  tech("phone-top"),                                                    // phone, 4.8, 2 km
  tech("phone-far", { }),                                               // phone, 4.8, 8 km
  tech("phone-low", { rating: 4.2 }),                                   // phone, 4.2, 2 km
  tech("laptop-top", { specializations: [spec("laptop", true)] }),      // laptop, 4.8, 2 km
  tech("phone-new", { rating: 0, specializations: [spec("smartphone")], badge: "id_verified" }), // unrated, unassessed
  tech("phone-pro", { badge: "community_trusted" }),                   // community trusted, 4 km
  tech("phone-away", { away_until: "2026-11-20" }),                     // on time off today
];
const distances = new Map<string, number | null>([
  ["phone-top", 2], ["phone-far", 8], ["phone-low", 2], ["laptop-top", 2],
  ["phone-new", 3], ["phone-pro", 4], ["phone-away", 1],
]);

// --------------------------------------------------- 1. nothing set = no-op

{
  const prefs = readPreferences(job());
  const result = applyClientPreferenceFilter(pool, distances, prefs, PHONE_DEVICES);
  check("no preferences: same candidates, same order",
    ids(result.kept) === ids(pool), ids(result.kept));
  check("no preferences: reported as inactive", result.active.length === 0);
  check("no preferences: the very same array is returned", result.kept === pool);
}

// ------------------------- 2. brief: Phone/Tablet + 4.5+ + 5 km, then ranked

{
  const prefs = readPreferences(job({
    pref_specialization: "phone_tablet", pref_min_rating: "4.5", pref_max_distance_km: 5,
  }));
  const result = applyClientPreferenceFilter(pool, distances, prefs, PHONE_DEVICES);
  check("phone + 4.5+ + 5 km keeps only qualifying phone techs",
    ids(result.kept) === "phone-top,phone-pro,phone-away", ids(result.kept));
  check("numeric rating arriving as a string is read as 4.5", prefs.minRating === 4.5);
  check("the laptop technician is removed (specialisation)",
    !result.kept.some((t) => t.id === "laptop-top"));
  check("8 km is removed by a 5 km limit",
    !result.kept.some((t) => t.id === "phone-far"));
  check("4.2 is removed by 4.5+", !result.kept.some((t) => t.id === "phone-low"));
  check("an unrated technician is removed by any minimum rating",
    !result.kept.some((t) => t.id === "phone-new"));
}

// ----------------------- 3. brief: Skill verified excludes ID-verified-only
//
// Since 20261115000002 the ladder is the Progressive Trust Badge stored on
// the technician, capped per job by whether they are skill verified for it.

{
  const prefs = readPreferences(job({ pref_min_trust: "skill_verified" }));
  const result = applyClientPreferenceFilter(pool, distances, prefs, PHONE_DEVICES);
  check("skill verified keeps skill verified AND community trusted",
    result.kept.some((t) => t.id === "phone-top") &&
      result.kept.some((t) => t.id === "phone-pro"));
  check("skill verified drops the ID-verified-only technician",
    !result.kept.some((t) => t.id === "phone-new"));
  check("skill verified is measured on THIS job's device",
    !result.kept.some((t) => t.id === "laptop-top"),
    "a laptop-assessed tech passed a phone job's skill gate");

  const pro = applyClientPreferenceFilter(
    pool, distances, readPreferences(job({ pref_min_trust: "community_trusted" })), PHONE_DEVICES,
  );
  check("community trusted keeps only the community trusted", ids(pro.kept) === "phone-pro", ids(pro.kept));

  const legacy = readPreferences(job({ pref_min_trust: "certified_pro" }));
  check("the retired certified_pro rung reads as No preference", legacy.minTrust === null);

  const id = applyClientPreferenceFilter(
    pool, distances, readPreferences(job({ pref_min_trust: "id_verified" })), PHONE_DEVICES,
  );
  check("ID verified keeps everyone with a badge", id.kept.length === pool.length);

  // The ladder is ordered: rung 3 requires rung 2 for this job.
  const trustedNotAssessedHere = tech("x", {
    badge: "community_trusted", specializations: [spec("laptop", true)],
  });
  check("a community trusted tech not assessed on this device sits on rung 1",
    trustRungOf(trustedNotAssessedHere, PHONE_DEVICES) === 1);
  check("no badge (below the baseline) sits on rung 0",
    trustRungOf(tech("y", { badge: null }), PHONE_DEVICES) === 0);
  check("an unknown badge value is not trusted",
    trustRungOf(tech("z", { badge: "Top Rated" }), PHONE_DEVICES) === 0);
}

// --- 3b. brief: Skill Verified only for Phone/Tablet is not matched for PC
//         Building jobs (when the client requires Skill verified or higher)

{
  const PC_BUILDING_DEVICES = ["desktop"];
  const phoneOnly = tech("phone-only", { badge: "skill_verified" });
  const pcBuilder = tech("pc-builder", {
    badge: "skill_verified", specializations: [spec("desktop", true)],
  });
  check("phone-only skill verification is rung 1 on a PC Building job",
    trustRungOf(phoneOnly, PC_BUILDING_DEVICES) === 1);
  const result = applyClientPreferenceFilter(
    [phoneOnly, pcBuilder],
    new Map([["phone-only", 2], ["pc-builder", 2]]),
    readPreferences(job({ device_type: "laptop", pref_min_trust: "skill_verified" })),
    PC_BUILDING_DEVICES,
  );
  check("a PC Building job requiring skill verified excludes the phone-only tech",
    ids(result.kept) === "pc-builder", ids(result.kept));
}

// ---------------------------------------------------------- 4. availability

{
  const now = applyClientPreferenceFilter(
    pool, distances, readPreferences(job({ pref_availability: "now" })), PHONE_DEVICES,
    { busy: new Set(["phone-top"]), awayOnDate: new Set() },
  );
  check("available now drops whoever is on time off today",
    !now.kept.some((t) => t.id === "phone-away"));
  check("available now drops whoever is on another unfinished job",
    !now.kept.some((t) => t.id === "phone-top"));

  const onDate = applyClientPreferenceFilter(
    pool, distances,
    readPreferences(job({ pref_availability: "on_date", pref_available_on: "2026-11-25" })),
    PHONE_DEVICES,
    { busy: new Set(), awayOnDate: new Set(["phone-pro"]) },
  );
  check("pick a date drops only who is away on that date",
    !onDate.kept.some((t) => t.id === "phone-pro") &&
      onDate.kept.some((t) => t.id === "phone-away"),
    ids(onDate.kept));

  const noDate = readPreferences(job({ pref_availability: "on_date", pref_available_on: null }));
  check("a date preference without a date is ignored, not applied",
    noDate.availability === null);
}

// ------------------------------------------------------ 5. invalid = ignored

{
  const prefs = readPreferences(job({
    pref_specialization: "toString", pref_max_distance_km: 7, pref_min_rating: 4.2,
    pref_min_trust: "gold_member",
  }));
  check("values outside the fixed options become No preference",
    prefs.specialization === null && prefs.maxDistanceKm === null &&
      prefs.minRating === null && prefs.minTrust === null);
}

// ------------------------- 6. brief: impossible combination => relax prompt

{
  const prefs = readPreferences(job({
    pref_specialization: "phone_tablet", pref_min_trust: "community_trusted", pref_max_distance_km: 3,
  }));
  const result = applyClientPreferenceFilter(pool, distances, prefs, PHONE_DEVICES);
  check("an impossible combination keeps nobody, without throwing", result.kept.length === 0);

  const distanceHint = result.relaxHints.find((h) => h.preference === "max_distance_km");
  check("hint: removing the 3 km limit brings back the 4 km certified pro",
    distanceHint?.would_match === 1, JSON.stringify(result.relaxHints));

  // Removing Community Trusted brings back four (everyone phone-capable within
  // 3 km); removing the 3 km limit brings back one. The message names the
  // relaxation that helps most.
  const message = relaxMessage(result, prefs);
  check("the message names the relaxation that helps most",
    message.includes("“Community Trusted or higher”") &&
      message.includes("bring back 4 technicians"),
    message);

  const hopeless = applyClientPreferenceFilter(
    [tech("only", { rating: 3.1, specializations: [spec("laptop")] })],
    new Map([["only", 9]]),
    readPreferences(job({
      pref_specialization: "phone_tablet", pref_min_rating: 4.5, pref_max_distance_km: 3,
    })),
    PHONE_DEVICES,
  );
  check("when no single relaxation helps, say relax more than one",
    relaxMessage(hopeless, readPreferences(job({
      pref_specialization: "phone_tablet", pref_min_rating: 4.5, pref_max_distance_km: 3,
    }))).includes("more than one"));
}

// ------------------------------------------------- 7. missing facts fail closed

{
  const result = applyClientPreferenceFilter(
    [tech("nowhere")], new Map([["nowhere", null]]),
    readPreferences(job({ pref_max_distance_km: 10 })), PHONE_DEVICES,
  );
  check("an unknown distance cannot satisfy a distance limit", result.kept.length === 0);

  const legacy = applyClientPreferenceFilter(
    [tech("old", { specializations: [], specialization: ["phone"] })], distances,
    readPreferences(job({ pref_specialization: "phone_tablet" })), PHONE_DEVICES,
  );
  check("a pre-registration account's legacy specialisation still counts",
    legacy.kept.length === 1);
}

// ----------------------------------- distance fallback (2026-11-17)

{
  // Limits are 3, 5 or 10 km. Nobody here is within 3 km; the nearest who
  // meets the 4.5 rating is 9 km away. phone-low (4.2) is nearer but fails
  // the rating, so it must stay out.
  const prefs = readPreferences(job({ pref_max_distance_km: 3, pref_min_rating: 4.5 }));
  const spread = new Map<string, number | null>([
    ["phone-top", 12], ["phone-far", 14], ["phone-low", 4], ["laptop-top", 9],
    ["phone-new", 13], ["phone-pro", 15], ["phone-away", 20],
  ]);
  const far = pool.filter((t) => t.id !== "phone-away");
  const result = applyClientPreferenceFilter(far, spread, prefs, PHONE_DEVICES);
  check("fallback: nobody within 3 km to begin with", result.kept.length === 0,
    ids(result.kept));
  const fb = distanceFallback(result, far, spread, prefs, PHONE_DEVICES);
  check("fallback: applies when distance alone is in the way", fb !== null);
  check("fallback: other preferences still hold (no 4.2 rating)",
    !!fb && !fb.kept.some((t) => t.id === "phone-low"), fb ? ids(fb.kept) : "");
  check("fallback: reports the limit and the nearest distance",
    !!fb && fb.fallback.wanted_km === 3 && fb.fallback.nearest_km === 9,
    JSON.stringify(fb?.fallback));
  check("fallback: the sentence names both",
    !!fb && distanceFallbackMessage(fb.fallback) ===
      "No technician within 3 km - the nearest is 9 km away.",
    fb ? distanceFallbackMessage(fb.fallback) : "");
}

{
  // Something IS within the limit: no fallback.
  const prefs = readPreferences(job({ pref_max_distance_km: 5 }));
  const result = applyClientPreferenceFilter(pool, distances, prefs, PHONE_DEVICES);
  check("fallback: not used when someone qualifies",
    distanceFallback(result, pool, distances, prefs, PHONE_DEVICES) === null);
}

{
  // Distance is not what is in the way (nobody has a 5.0 rating): no fallback.
  const prefs = readPreferences(job({ pref_max_distance_km: 3, pref_min_rating: 5 }));
  const result = applyClientPreferenceFilter(pool, distances, prefs, PHONE_DEVICES);
  check("fallback: not used when removing distance brings back nobody",
    distanceFallback(result, pool, distances, prefs, PHONE_DEVICES) === null);
}

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
