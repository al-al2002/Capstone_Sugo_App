/**
 * Stage 1 ladder, client trust, the smoothed rating, the service-radius
 * penalty and time off, all pinned.
 *
 * These are the parts of the matching engine where a mistake is silent: a
 * wrong rung ordering does not throw, it just quietly ranks the wrong
 * technician first, and nobody notices until a client is sent someone who has
 * never been assessed on their machine.
 *
 * Run with Node's TypeScript stripping (no Deno needed):
 *
 *   cd supabase/functions/match-technician/scoring
 *   node --experimental-strip-types matching_rules.test.ts
 *
 * Every module under test is pure - no Deno APIs, no network - which is what
 * makes running it outside the edge runtime possible.
 */
import { ratingScore, specializationMatchScore } from "./suitability.ts";
import {
  availabilityScore,
  clientTrustScore,
  formatAwayUntil,
  proximityScore,
} from "./acceptance.ts";

const job = (brand: string | null, deviceType = "laptop") => ({
  id: "j", client_id: "c", device_type: deviceType, problem_symptom: "screen",
  has_physical_damage: false, classification_confidence: null, service_path: null,
  urgency: "can_wait", latitude: 7.07, longitude: 125.61, budget_min: null,
  budget_max: null, preferred_schedule: null, description: null, photo_urls: null,
  status: "pending", assigned_technician_id: null, brand, device_detail: null,
}) as any;

const tech = (specs: any[]) => ({
  id: "t", skill_tags: [], tier: "standard", specialization: [], is_verified: true,
  badge: null, rating: 0, total_jobs: 0, current_workload: 0,
  latitude: null, longitude: null, base_latitude: 7.07, base_longitude: 125.61,
  service_radius_km: 10, verification_tier: "verified", identity_approved: true,
  specializations: specs, created_at: null,
}) as any;

const ctx = { deviceCandidates: ["laptop", "desktop"] } as any;

const spec = (device: string, brand: string, level: string | null, verified: boolean) =>
  ({ device_type: device, brand, skill_level: level, verified, track: "computer_repair" });

let failures = 0;
function check(name: string, actual: number, expected: number) {
  const ok = Math.abs(actual - expected) < 1e-9;
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(52)} ${actual}${ok ? "" : ` (expected ${expected})`}`);
}

function compare(name: string, bigger: number, smaller: number) {
  const ok = bigger > smaller;
  if (!ok) failures++;
  console.log(
    `${ok ? "PASS" : "FAIL"}  ${name.padEnd(52)} ${bigger.toFixed(3)} > ${smaller.toFixed(3)}`,
  );
}

function above(name: string, actual: number, floor: number) {
  const ok = actual > floor;
  if (!ok) failures++;
  console.log(
    `${ok ? "PASS" : "FAIL"}  ${name.padEnd(52)} ${actual.toFixed(3)}`,
  );
}

// The priority ladder, in the order the brief sets out.
check("(a) verified Expert, exact brand + device",
  specializationMatchScore(job("Apple"), tech([spec("laptop","Apple","expert",true)]), ctx).value, 1.00);

check("(b) verified Intermediate, exact brand + device",
  specializationMatchScore(job("Apple"), tech([spec("laptop","Apple","intermediate",true)]), ctx).value, 0.85);

check("(c) verified Expert, device only (other brand)",
  specializationMatchScore(job("Apple"), tech([spec("laptop","Dell","expert",true)]), ctx).value, 0.70);

check("(c) verified Intermediate, device only",
  specializationMatchScore(job("Apple"), tech([spec("laptop","Dell","intermediate",true)]), ctx).value, 0.60);

check("(d) unverified claim on exact brand",
  specializationMatchScore(job("Apple"), tech([spec("laptop","Apple",null,false)]), ctx).value, 0.35);

check("(d) unverified claim on device only",
  specializationMatchScore(job("Apple"), tech([spec("laptop","Dell",null,false)]), ctx).value, 0.35);

check("no specialisation covers the device",
  specializationMatchScore(job("Apple"), tech([spec("aircon","LG","expert",true)]), ctx).value, 0.10);

// "Others" / blank brand must degrade to device-only, not exclude everyone.
check('brand "Others" falls back to device match',
  specializationMatchScore(job("Others"), tech([spec("laptop","Dell","expert",true)]), ctx).value, 0.70);

check("null brand falls back to device match",
  specializationMatchScore(job(null), tech([spec("laptop","Dell","expert",true)]), ctx).value, 0.70);

// Desktop must match a laptop-category job - the vocabulary bridge.
check("desktop specialist matches a 'laptop' category job",
  specializationMatchScore(job("Apple"), tech([spec("desktop","Apple","expert",true)]), ctx).value, 1.00);

// Ordering property: exact brand always beats device-only.
const exact = specializationMatchScore(job("Apple"), tech([spec("laptop","Apple","intermediate",true)]), ctx).value;
const deviceOnly = specializationMatchScore(job("Apple"), tech([spec("laptop","Dell","expert",true)]), ctx).value;
console.log(`${exact > deviceOnly ? "PASS" : "FAIL"}  (b) exact-brand Intermediate outranks (c) device Expert   ${exact} > ${deviceOnly}`);
if (!(exact > deviceOnly)) failures++;

// Client trust: soft, never zero.
const trust = (level: string, noShows = 0) =>
  clientTrustScore({ trustLevel: level, noShowCount: noShows, averageRating: null } as any).value;

check("client trust: new", trust("new"), 0.70);
check("client trust: verified", trust("verified"), 0.90);
check("client trust: trusted", trust("trusted"), 1.00);
check("client trust: new + 2 no-shows", trust("new", 2), 0.54);
check("no-show penalty is capped", trust("new", 99), 0.40);

// ---------------------------------------------------------------------------
// Client rating, smoothed. A thin history must not outrank a long good one.
// ---------------------------------------------------------------------------
const rated = (rating: number, jobs: number) =>
  ratingScore({ rating, total_jobs: jobs } as any).value;

// Unrated sits exactly on the prior (4.0 on a 1-5 scale -> 0.75), because a
// technician with no reviews has not been judged badly, only not judged.
check("rating: never rated sits on the prior", rated(0, 0), 0.75);
check("rating: a 0 average is treated as unrated", rated(0, 20), 0.75);

// One perfect review barely moves off the prior; fifty good ones do.
const onePerfect = rated(5, 1);
const fiftyGood = rated(4.7, 50);
compare("4.7 over 50 jobs beats 5.0 over 1", fiftyGood, onePerfect);

// Rating must be able to push down as well as up, or it is only ever a bonus.
const poor = rated(2.0, 40);
compare("a poor record scores below the prior", 0.75, poor);

// ---------------------------------------------------------------------------
// Service radius: a penalty now, not an exclusion. Distant technicians still
// score - they just lose to anyone closer.
// ---------------------------------------------------------------------------
const prox = (km: number, radius: number | null) =>
  proximityScore(km, radius).value ?? -1;

check("proximity: at the door", prox(0, 10), 1);
check("proximity: 5 km inside a 10 km radius", prox(5, 10), 0.8);
check("proximity: unknown distance stays null",
  proximityScore(null, 10).value === null ? 1 : 0, 1);
check("proximity: no declared radius is not penalised", prox(5, null), 0.8);

// Outside the declared radius the score collapses but stays above zero, which
// is the whole point: they remain rankable instead of deleted from the pool.
const justOutside = prox(11, 10);
const farOutside = prox(21, 10);
above("1 km past the radius still scores", justOutside, 0);
compare("1 km past the radius is well below inside", 0.6, justOutside);
above("21 km out still scores above zero", farOutside, 0);
compare("further out scores lower", justOutside, farOutside);

// The near technician has to win. This is the client's actual request.
compare("nearby outscores distant", prox(2, 10), farOutside);

// Time off is the whole of availability. A technician on vacation scores
// zero - still ranked, never deleted from the pool - and the retired online
// switch no longer counts either way: a value left over from it must not
// sink someone who is working, nor rescue someone who is away.
const onVacation = { ...tech([]), is_available: true, away_until: "2026-09-27" };
const working = { ...tech([]), is_available: true, away_until: null };
const leftOffline = { ...tech([]), is_available: false, away_until: null };
check("vacation scores zero", availabilityScore(onVacation).value, 0);
check("working scores full", availabilityScore(working).value, 1);
check("a leftover offline switch is ignored", availabilityScore(leftOffline).value, 1);
check("vacation note names the end date",
  availabilityScore(onVacation).note.includes("until Sep 27") ? 1 : 0, 1);
// A date-only value must not shift a day in any time zone.
check("end date prints as the same calendar day",
  formatAwayUntil("2026-12-31") === "Dec 31" ? 1 : 0, 1);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
