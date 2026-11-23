/**
 * Stage 1 ladder, the smoothed rating, time off, and the Table 11 signals
 * (travel burden, price fit, coverage fit, weather readiness), all pinned.
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
import { specializationMatchScore } from "./suitability.ts";
import {
  conditionsReadinessScore,
  coverageFitScore,
  priceFitScore,
  travelBurdenScore,
} from "./acceptance.ts";
import {
  availabilityScore,
  formatAwayUntil,
  ratingScore,
} from "./recommendation.ts";

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
// Coverage fit: the service radius is a penalty, not an exclusion. Distant
// technicians still score - they just lose to anyone inside their area.
// ---------------------------------------------------------------------------
const cover = (km: number, radius: number | null) =>
  coverageFitScore(km, radius).value ?? -1;

check("coverage: at the door", cover(0, 10), 1);
check("coverage: anywhere inside the radius is full marks", cover(9.9, 10), 1);
check("coverage: unknown distance stays null",
  coverageFitScore(null, 10).value === null ? 1 : 0, 1);
check("coverage: no declared radius stays null (not guessed)",
  coverageFitScore(5, null).value === null ? 1 : 0, 1);

// Outside the declared radius the score falls but stays above zero, which is
// the whole point: they remain rankable instead of deleted from the pool.
const justOutside = cover(11, 10);
const farOutside = cover(21, 10);
above("1 km past the radius still scores", justOutside, 0);
compare("1 km past the radius is below inside", 1, justOutside);
above("21 km out still scores above zero", farOutside, 0);
compare("further out scores lower", justOutside, farOutside);
check("reaches zero at the 50 km ceiling", cover(50, 10), 0);

// ---------------------------------------------------------------------------
// Travel burden: traffic-adjusted travel time, scaled by the service path.
// ---------------------------------------------------------------------------
const travel = (minutes: number | null, exposure = 1) =>
  travelBurdenScore(minutes, exposure, true).value ?? -1;

check("travel: at the door", travel(0), 1);
check("travel: 15 min on a home visit", travel(15), 0.75);
check("travel: an hour or more is zero", travel(75), 0);
check("travel: unknown location stays null",
  travelBurdenScore(null, 1, true).value === null ? 1 : 0, 1);
check("travel: a remote IT job barely counts the trip", travel(60, 0.1), 0.9);
// The near technician has to win. This is the client's actual request.
compare("nearby outscores distant", travel(6), travel(40));

// ---------------------------------------------------------------------------
// Price fit: the fixed price against each tier's minimum (₱300/₱500/₱800).
// ---------------------------------------------------------------------------
const priced = (symptom: string, tier: string, urgency = "can_wait") =>
  priceFitScore(
    { ...job(null), problem_symptom: symptom, urgency },
    { ...tech([]), tier },
  );

check("price: ₱600 job meets a standard minimum", priced("laptop_blue_screen", "standard").value, 1);
check("price: ₱600 job meets a pro minimum", priced("laptop_blue_screen", "pro").value, 1);
// ₱600 / ₱800 = 0.75 of the minimum -> halfway between 0.5 and 1.
check("price: ₱600 job is half-fit for elite", priced("laptop_blue_screen", "elite").value, 0.5);
check("price: ₱400 job is zero for elite (half the minimum)",
  priced("cctv_offline", "elite").value, 0);
check("price: urgent ₱600 job becomes ₱720", priced("laptop_blue_screen", "elite", "need_today").pricePhp ?? 0, 720);
compare("price: the urgent fee makes an elite more willing",
  priced("laptop_blue_screen", "elite", "need_today").value,
  priced("laptop_blue_screen", "elite").value);
check("price: no single price is neutral", priced("not_sure", "elite").value, 0.70);
check("price: per-camera fee is neutral", priced("cctv_new_install", "elite").value, 0.70);
compare("price: standard is more willing than elite on a small job",
  priced("phone_software_stuck", "standard").value,
  priced("phone_software_stuck", "elite").value);

// ---------------------------------------------------------------------------
// Weather & traffic readiness: the technician's own answers while it rains or
// the traffic is heavy; an estimate from the weather and their trip otherwise.
// ---------------------------------------------------------------------------
const conditions = (
  severity: number | null,
  congestion: number | null = 0.1,
  exposure = 1,
) => ({
  weather: { available: severity !== null, severity, label: "rain" },
  traffic: {
    available: congestion !== null, congestion, roadClosure: false,
    currentSpeed: 30, label: null,
  },
  travelExposure: exposure,
}) as any;
const said = (rain: string | null, traffic: boolean | null = null) =>
  ({ ...tech([]), rain_travel: rain, heavy_traffic_travel: traffic });
const ready = (
  technician: any,
  severity: number | null,
  minutes: number | null,
  congestion: number | null = 0.1,
  exposure = 1,
) =>
  conditionsReadinessScore(technician, conditions(severity, congestion, exposure), minutes)
    .value ?? -1;

// Not answered: the estimate, exactly as before the question existed.
check("not answered, clear sky: full marks", ready(said(null), 0, 45), 1);
check("not answered, API down: stays null",
  conditionsReadinessScore(said(null), conditions(null, null), 10).value === null ? 1 : 0, 1);
// Rain (0.55) over a 30-min ride: 1 - 0.55 x 1 x 0.5.
check("not answered, rain over half an hour: estimated", ready(said(null), 0.55, 30), 0.725);
compare("not answered, in rain the nearer one is readier",
  ready(said(null), 0.55, 5), ready(said(null), 0.55, 45));

// Answered, in ordinary rain (0.55).
check("rain: 'even in heavy rain' scores 1", ready(said("any"), 0.55, 30), 1);
check("rain: 'not in heavy rain' still scores 1", ready(said("not_heavy"), 0.55, 30), 1);
check("rain: 'never in rain' scores 0", ready(said("never"), 0.55, 30), 0);

// Answered, in heavy rain or a storm (0.85 / 1.0).
check("heavy rain: 'even in heavy rain' scores 1", ready(said("any"), 0.85, 30), 1);
check("heavy rain: 'not in heavy rain' scores 0", ready(said("not_heavy"), 0.85, 30), 0);
check("storm: 'not in heavy rain' scores 0", ready(said("not_heavy"), 1, 30), 0);

// The point of asking: in rain, yes > unknown > no.
compare("in rain, 'yes' beats not answered",
  ready(said("any"), 0.85, 30), ready(said(null), 0.85, 30));
compare("in rain, not answered beats 'no'",
  ready(said(null), 0.85, 30), ready(said("never"), 0.85, 30));

// No rain: the rain answer is not used - a dry day is a dry day for everyone.
check("drizzle (0.35): 'never in rain' is not penalised as if raining",
  ready(said("never"), 0.35, 30), ready(said(null), 0.35, 30));

// Heavy traffic (congestion 0.7).
check("heavy traffic: 'still go' scores 1", ready(said(null, true), 0, 30, 0.7), 1);
check("heavy traffic: 'avoid it' scores 0", ready(said(null, false), 0, 30, 0.7), 0);
// Not answered: 1 - 0.7 x 1 x 0.5 = 0.65.
check("heavy traffic, not answered: estimated", ready(said(null), 0, 30, 0.7), 0.65);
check("light traffic: the traffic answer is not used",
  ready(said(null, false), 0, 30, 0.3), 1);

// Both at once: the lower part decides - willing in rain but not in traffic
// is not going today.
check("rain yes + traffic no = 0", ready(said("any", false), 0.55, 30, 0.7), 0);
check("rain yes + traffic yes = 1", ready(said("any", true), 0.85, 30, 0.7), 1);

// Scaled by travel exposure: a shop pickup (0.6) takes most of a "no".
check("shop pickup: 'never in rain' is 1 - 0.6 = 0.4",
  ready(said("never"), 0.55, 30, 0.1, 0.6), 0.4);

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
