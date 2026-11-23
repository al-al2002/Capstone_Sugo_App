/**
 * Rule-based weighting, the Table 10 final score, the paper's weights and the
 * client-facing reasons, all pinned.
 *
 * Like the Stage 1 ladder, these fail silently when wrong: a rule that never
 * fires, or fires on missing data, does not throw - it just ranks someone
 * else first, and the demo still looks fine.
 *
 * Run with Node's TypeScript stripping (no Deno needed):
 *
 *   cd supabase/functions/match-technician/scoring
 *   node --experimental-strip-types recommendation.test.ts
 */
import { deriveSignals, MATCHING_RULES, reweight, selectRules } from "./rules.ts";
import { responseRecord, scoreRecommendation } from "./recommendation.ts";
import { scoreAcceptance } from "./acceptance.ts";
import { applyPreviousTechnicianPriority } from "./rank.ts";
import { buildReasons } from "./reasons.ts";
import { combine } from "./weighting.ts";
import {
  ACCEPTANCE_WEIGHTS,
  FINAL_WEIGHTS,
  SUITABILITY_WEIGHTS,
} from "./constants.ts";
import type { StageResult } from "./types.ts";

let failures = 0;
function check(name: string, ok: boolean, detail = "") {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(58)} ${detail}`);
}
const near = (a: number, b: number) => Math.abs(a - b) < 1e-3;

const job = (over: Record<string, unknown> = {}) => ({
  id: "j", client_id: "c", device_type: "laptop", problem_symptom: "no_power",
  has_physical_damage: false, classification_confidence: "high",
  service_path: "home_service", urgency: "can_wait", latitude: 7.07,
  longitude: 125.61, budget_min: null, budget_max: null,
  preferred_schedule: null, description: null, photo_urls: null,
  status: "pending", assigned_technician_id: null, brand: null,
  device_detail: null, ...over,
}) as any;

const tech = (over: Record<string, unknown> = {}) => ({
  id: "t", skill_tags: [], tier: "standard", specialization: [],
  is_verified: true, badge: null, rating: 0, total_jobs: 0,
  current_workload: 0, latitude: null, longitude: null, base_latitude: 7.07,
  base_longitude: 125.61, service_radius_km: 10, verification_tier: "verified",
  identity_approved: true, specializations: [], created_at: null,
  away_until: null, ...over,
}) as any;

const traffic = (over: Record<string, unknown> = {}) => ({
  available: true, currentSpeed: 30, freeFlowSpeed: 40, congestion: 0.1,
  roadClosure: false, label: "clear roads", ...over,
}) as any;

const weather = (over: Record<string, unknown> = {}) => ({
  available: true, condition: "Clear", description: "clear sky", tempC: 30,
  severity: 0, label: "clear weather", ...over,
}) as any;

const offline = { available: false, congestion: null, severity: null } as any;

// ------------------------------------------------------------ Step 2: signals
{
  const s = deriveSignals(
    job({ urgency: "need_today" }), "home_service", traffic(),
    weather({ severity: 0.55 }),
  );
  check("urgent + rain + home visit are all detected",
    ["urgent", "rain", "on_site", "technology"].every((x) => s.includes(x as any)),
    s.join(","));

  const rainOnly = deriveSignals(job(), "home_service", traffic(), weather({ severity: 0.55 }));
  check("ordinary rain (0.55) is rain, not heavy rain",
    rainOnly.includes("rain") && !rainOnly.includes("heavy_rain"), rainOnly.join(","));

  const downpour = deriveSignals(job(), "home_service", traffic(), weather({ severity: 0.85 }));
  check("heavy rain (0.85) holds both rain and heavy rain",
    downpour.includes("rain") && downpour.includes("heavy_rain"), downpour.join(","));

  const storm = deriveSignals(job(), "home_service", traffic(), weather({ severity: 1 }));
  check("a thunderstorm (1.0) counts as heavy rain", storm.includes("heavy_rain"));

  check("drizzle (0.35) is not rain",
    !deriveSignals(job(), "home_service", traffic(), weather({ severity: 0.35 }))
      .includes("rain"));

  check("weather API down means no rain signal - not an error",
    !deriveSignals(job(), "home_service", traffic(), offline).includes("rain"));

  check("congestion 0.65 is heavy traffic",
    deriveSignals(job(), "home_service", traffic({ congestion: 0.65 }), weather())
      .includes("heavy_traffic"));

  check("a road closure counts as heavy traffic",
    deriveSignals(job(), "home_service", traffic({ roadClosure: true }), weather())
      .includes("heavy_traffic"));

  check("traffic API down means no traffic signal",
    !deriveSignals(job(), "home_service", offline, weather())
      .includes("heavy_traffic"));

  check("a shop pickup is not an on-site visit",
    !deriveSignals(job(), "pickup", traffic(), weather()).includes("on_site"));

  check("appliance jobs are flagged as appliance, not technology",
    deriveSignals(job({ device_type: "appliance" }), "home_service", traffic(), weather())
      .includes("appliance"));
}

// ---------------------------------------------------------- Step 3: rules
{
  const sel = selectRules(["urgent", "rain", "on_site", "technology"]);
  const ids = sel.applied.map((r) => r.id);
  check("urgent + rain + visit fires the rain rule and the urgency rule",
    ids.includes("urgent_visit_in_rain") && ids.includes("urgent_request"),
    ids.join(","));
  check("...and not the traffic or appliance rules",
    !ids.includes("heavy_traffic_visit") && !ids.includes("appliance_repair"));

  check("multipliers on the same factor compose (1.4 x 1.3)",
    near(sel.multipliers.recommendation.availability, 1.82),
    String(sel.multipliers.recommendation.availability));

  const stacked = selectRules(["urgent"], [
    { id: "a", label: "a", rationale: "", when: ["urgent"], adjust: { acceptance: { travel_burden: 1.8 } } },
    { id: "b", label: "b", rationale: "", when: ["urgent"], adjust: { acceptance: { travel_burden: 1.8 } } },
  ]);
  check("stacked rules are capped at 2.0",
    stacked.multipliers.acceptance.travel_burden === 2,
    String(stacked.multipliers.acceptance.travel_burden));

  const calm = selectRules(["technology"]);
  check("an ordinary request fires no rule", calm.applied.length === 0);

  // Rain on its own now moves the ranking - not only when the job is urgent.
  const wet = selectRules(["rain", "on_site", "technology"]);
  const wetIds = wet.applied.map((r) => r.id);
  check("rain on a can-wait home visit fires 'Rain on the way'",
    wetIds.includes("rain_visit") && !wetIds.includes("heavy_rain_visit"),
    wetIds.join(","));

  const pour = selectRules(["rain", "heavy_rain", "on_site", "technology"]);
  const pourIds = pour.applied.map((r) => r.id);
  check("heavy rain fires both rain rules",
    pourIds.includes("rain_visit") && pourIds.includes("heavy_rain_visit"),
    pourIds.join(","));
  check("...and they compose: travel burden 1.3 x 1.3 = 1.69",
    near(pour.multipliers.acceptance.travel_burden, 1.69),
    String(pour.multipliers.acceptance.travel_burden));
  check("heavy rain re-weights harder than rain",
    pour.multipliers.acceptance.conditions_readiness >
      wet.multipliers.acceptance.conditions_readiness);

  check("rain on a shop repair fires no rain rule (no home visit)",
    selectRules(["rain", "heavy_rain", "technology"]).applied.length === 0);

  const jam = selectRules(["heavy_traffic", "on_site", "technology"]);
  check("heavy traffic on a home visit fires the traffic rule",
    jam.applied.some((r) => r.id === "heavy_traffic_visit"));

  const both = selectRules(["rain", "heavy_traffic", "on_site", "technology"]);
  check("rain + heavy traffic: travel burden 1.3 x 1.5 = 1.95, under the cap",
    near(both.multipliers.acceptance.travel_burden, 1.95),
    String(both.multipliers.acceptance.travel_burden));

  const worst = selectRules(["urgent", "rain", "heavy_rain", "heavy_traffic", "on_site"]);
  check("everything at once is still capped at 2.0",
    Object.values(worst.multipliers.acceptance).every((m) => m <= 2) &&
      Object.values(worst.multipliers.recommendation).every((m) => m <= 2));

  check("every rule's conditions are real signals",
    MATCHING_RULES.every((r) => r.when.every((w) =>
      ["urgent", "rain", "heavy_rain", "heavy_traffic", "on_site", "appliance", "technology"]
        .includes(w))));

  // A rule that names a factor no stage scores would silently do nothing.
  const known: Record<string, string[]> = {
    suitability: Object.keys(SUITABILITY_WEIGHTS),
    acceptance: Object.keys(ACCEPTANCE_WEIGHTS),
    recommendation: Object.keys(FINAL_WEIGHTS),
  };
  check("every rule adjusts a factor that exists",
    MATCHING_RULES.every((r) =>
      Object.entries(r.adjust).every(([stage, factors]) =>
        Object.keys(factors!).every((f) => known[stage].includes(f)))));
}

// ------------------------------------------- the paper's weights, exactly
const same = (a: Record<string, number>, b: Record<string, number>) =>
  Object.keys(a).length === Object.keys(b).length &&
  Object.entries(b).every(([k, v]) => a[k] === v);

check("Table 10 weights: 0.45 / 0.40 / 0.05 / 0.05 / 0.05",
  same(FINAL_WEIGHTS, {
    suitability: 0.45, acceptance: 0.40, rating: 0.05, availability: 0.05,
    trust_badge: 0.05,
  }));
check("Table 11 weights: 0.30 / 0.25 / 0.20 / 0.15 / 0.10",
  same(ACCEPTANCE_WEIGHTS, {
    travel_burden: 0.30, workload: 0.25, price_fit: 0.20, coverage_fit: 0.15,
    conditions_readiness: 0.10,
  }));

// --------------------------------------------------------- reweighting maths
const acceptanceFor = (travel: number, workload: number): StageResult =>
  combine([
    { key: "travel_burden", label: "", value: travel, weight: 0.30 },
    { key: "workload", label: "", value: workload, weight: 0.25 },
    { key: "price_fit", label: "", value: 1, weight: 0.20 },
    { key: "coverage_fit", label: "", value: 1, weight: 0.15 },
    { key: "conditions_readiness", label: "", value: 0.5, weight: 0.10 },
  ]);

{
  const stage = acceptanceFor(0.9, 1);
  const rain = selectRules(["urgent", "rain", "on_site"]).multipliers.acceptance;
  const out = reweight(stage, rain);
  const sum = out.factors.reduce((s, f) => s + f.weight, 0);
  check("re-weighted weights still sum to 1", near(sum, 1), sum.toFixed(4));
  check("a boosted factor carries its base weight for the demo view",
    out.factors.find((f) => f.key === "travel_burden")!.base_weight !== undefined);
  check("no multipliers returns the stage untouched", reweight(stage, {}) === stage);

  // The point of the rule: in the rain, the near technician gains on the far one.
  const nearTech = acceptanceFor(0.9, 1);
  const farTech = acceptanceFor(0.2, 1);
  const gapBefore = nearTech.score - farTech.score;
  const gapAfter = reweight(nearTech, rain).score - reweight(farTech, rain).score;
  check("rain + urgency widens the lead of the nearer technician",
    gapAfter > gapBefore, `${gapBefore.toFixed(3)} -> ${gapAfter.toFixed(3)}`);

  // The same, with no urgency: rain alone now moves the ranking, and a
  // downpour moves it further than ordinary rain.
  const showers = selectRules(["rain", "on_site"]).multipliers.acceptance;
  const downpour = selectRules(["rain", "heavy_rain", "on_site"]).multipliers.acceptance;
  const gapRain = reweight(nearTech, showers).score - reweight(farTech, showers).score;
  const gapHeavy = reweight(nearTech, downpour).score - reweight(farTech, downpour).score;
  check("rain alone (can wait) widens the nearer technician's lead",
    gapRain > gapBefore, `${gapBefore.toFixed(3)} -> ${gapRain.toFixed(3)}`);
  check("heavy rain widens it further than rain",
    gapHeavy > gapRain, `${gapRain.toFixed(3)} -> ${gapHeavy.toFixed(3)}`);

  const withBoost: StageResult = {
    score: 0.68,
    factors: [
      { key: "skill_tag", label: "", value: 0.5, weight: 0.5, contribution: 0.25 },
      { key: "specialization", label: "", value: 0.7, weight: 0.5, contribution: 0.35 },
      { key: "cold_start", label: "", value: 1, weight: 0.08, contribution: 0.08 },
    ],
  };
  const boosted = reweight(withBoost, { specialization: 2 });
  check("the cold-start boost survives re-weighting unchanged",
    boosted.factors.some((f) => f.key === "cold_start" && f.contribution === 0.08));
}

// --------------------------------------------- response rate (reasons only)
{
  const fresh = responseRecord(undefined);
  check("no offers answered sits at the 0.75 response prior",
    near(fresh.responseRate, 0.75), String(fresh.responseRate));
  check("reliable responder rises above the prior",
    responseRecord({ accepted: 10, declined: 0 }).responseRate > 0.75);
  check("serial decliner falls below the prior",
    responseRecord({ accepted: 0, declined: 5 }).responseRate < 0.75);
}

// ------------------------------------------- Table 10, the final score
const stage = (score: number): StageResult => ({ score, factors: [] });
const finalScore = (
  skill: number,
  acceptance: number,
  rating: number,
  availability: number,
  badge: number,
) =>
  scoreRecommendation({
    suitability: stage(skill),
    acceptance: stage(acceptance),
    rating: { value: rating, note: "" },
    availability: { value: availability, note: "" },
    trustBadge: { value: badge, note: "" },
    multipliers: {},
  });

{
  // The paper's own worked example, Table 10. Row 2 was printed as "Location
  // proximity"; it is Acceptance likelihood now, with the same numbers.
  const a = finalScore(0.90, 0.85, 0.88, 1.00, 0.80);
  const b = finalScore(0.70, 0.95, 0.92, 0.80, 0.75);
  check("Table 10 example: Provider A = 0.879", Math.abs(a.score - 0.879) < 1e-9,
    String(a.score));
  check("Table 10 example: Provider B = 0.8185", Math.abs(b.score - 0.8185) < 1e-9,
    String(b.score));
  check("Table 10 example: A ranks above B", a.score > b.score);

  const sum = a.factors.reduce((s, f) => s + f.weight, 0);
  check("final weights sum to 1", near(sum, 1), sum.toFixed(4));
  check("can-do-the-job outranks merely-likely (0.9/0.5 vs 0.5/0.9)",
    finalScore(0.9, 0.5, 0.75, 1, 0.55).score > finalScore(0.5, 0.9, 0.75, 1, 0.55).score);
  check("being on vacation costs exactly the 0.05 availability weight",
    near(
      finalScore(0.8, 0.7, 0.75, 1, 0.55).score -
        finalScore(0.8, 0.7, 0.75, 0, 0.55).score,
      0.05,
    ));
}

// ------------------------------------------------------------------ reasons
const reasonsFor = (over: Record<string, unknown>) => buildReasons({
  job: job(),
  technician: tech(),
  suitability: { score: 0.7, factors: [{ key: "specialization", label: "", value: 0.7, weight: 0.3, contribution: 0.21 }] },
  acceptance: stage(0.7),
  accuracy: { similarRepairs: 0, sameDeviceRepairs: 0, signal: 0.7, rerouteRate: 0, averageRating: null },
  signals: ["technology", "on_site"],
  distanceKm: 2.1,
  etaMinutes: 6,
  workload: 0,
  coldStart: false,
  history: undefined,
  responseRate: 0.75,
  answeredOffers: 0,
  ...over,
});
const codes = (r: { code: string }[]) => r.map((x) => x.code);

check("fixed prices: no budget reason, even on an old job with a budget",
  !codes(reasonsFor({ job: job({ budget_max: 500 }) }))
    .some((c) => c.startsWith("budget") || c === "over_budget"));
{
  const away = reasonsFor({ technician: tech({ away_until: "2026-10-02" }) });
  check("on vacation: caveat shown, 'free now' never claimed",
    codes(away).includes("on_vacation") && !codes(away).includes("free_now"));
}
check("first-time client: no 'you rated them' reason",
  !codes(reasonsFor({})).some((c) => c.includes("by_you")));
check("a 4.8 rating over 2 jobs is not quoted",
  !codes(reasonsFor({ technician: tech({ rating: 4.8, total_jobs: 2 }) })).includes("rating"));
check("a 4.8 rating over 30 jobs is quoted",
  codes(reasonsFor({ technician: tech({ rating: 4.8, total_jobs: 30 }) })).includes("rating"));
check("heavy traffic + close: 'beats the traffic' is earned",
  codes(reasonsFor({ signals: ["heavy_traffic", "on_site"] })).includes("beats_traffic"));
check("clear roads: 'beats the traffic' is not claimed",
  !codes(reasonsFor({})).includes("beats_traffic"));
check("heavy rain: the short-trip reason says so",
  reasonsFor({ signals: ["rain", "heavy_rain", "on_site"] })
    .some((r) => r.code === "short_trip_rain" && r.text.includes("heavy rain")));
check("positives are listed before caveats", (() => {
  const r = reasonsFor({ technician: tech({ away_until: "2026-10-02" }) });
  const firstCaveat = r.findIndex((x) => x.kind === "caveat");
  return firstCaveat === -1 || r.slice(firstCaveat).every((x) => x.kind === "caveat");
})());

// ------------------------------------- travel in rain / traffic (2026-11-22)
check("heavy rain + said 'even in heavy rain': positive reason",
  reasonsFor({
    signals: ["rain", "heavy_rain", "on_site"],
    technician: tech({ rain_travel: "any" }),
  }).some((r) => r.code === "travels_in_rain" && r.kind === "positive"));
check("heavy rain + said 'not in heavy rain': caveat, not hidden",
  reasonsFor({
    signals: ["rain", "heavy_rain", "on_site"],
    technician: tech({ rain_travel: "not_heavy" }),
  }).some((r) => r.code === "no_rain_travel" && r.kind === "caveat"));
check("ordinary rain + said 'not in heavy rain': still a positive",
  reasonsFor({
    signals: ["rain", "on_site"],
    technician: tech({ rain_travel: "not_heavy" }),
  }).some((r) => r.code === "travels_in_rain"));
check("dry day: no rain claim either way",
  !codes(reasonsFor({ technician: tech({ rain_travel: "never" }) }))
    .some((c) => c.includes("rain")));
check("not answered: no rain claim either way",
  !codes(reasonsFor({ signals: ["rain", "on_site"] })).some((c) => c.includes("rain_travel")));
check("heavy traffic + said 'avoid it': caveat",
  codes(reasonsFor({
    signals: ["heavy_traffic", "on_site"],
    technician: tech({ heavy_traffic_travel: false }),
  })).includes("avoids_traffic"));
{
  // A short trip they said they will not make is not a reason to pick them.
  const refuses = codes(reasonsFor({
    signals: ["rain", "heavy_rain", "heavy_traffic", "on_site"],
    technician: tech({ rain_travel: "not_heavy", heavy_traffic_travel: false }),
    distanceKm: 2, etaMinutes: 8,
  }));
  check("said no to heavy rain: 'short trip in the rain' is not also claimed",
    refuses.includes("no_rain_travel") && !refuses.includes("short_trip_rain"),
    refuses.join(","));
  check("said they avoid traffic: 'beats the traffic' is not also claimed",
    refuses.includes("avoids_traffic") && !refuses.includes("beats_traffic"),
    refuses.join(","));
}
check("heavy traffic + said 'still go': positive",
  codes(reasonsFor({
    signals: ["heavy_traffic", "on_site"],
    technician: tech({ heavy_traffic_travel: true }),
  })).includes("travels_in_traffic"));

// Worked example: two technicians identical in every way, 6 km from a home
// visit, in heavy rain. Only their answer to "will you travel in the rain?"
// differs. Printed so the numbers can be quoted.
{
  const ctx = {
    traffic: traffic({ currentSpeed: 30, congestion: 0.2 }),
    weather: weather({ severity: 0.85, label: "heavy intensity rain" }),
    travelExposure: 1,
  } as any;
  const signals = deriveSignals(job(), "home_service", ctx.traffic, ctx.weather);
  const rules = selectRules(signals);
  const scoreFor = (rain: string | null) => {
    const s2 = reweight(
      scoreAcceptance(job({ problem_symptom: "laptop_blue_screen" }), tech({ rain_travel: rain }), ctx, 6).stage,
      rules.multipliers.acceptance,
    );
    const final = scoreRecommendation({
      suitability: stage(0.8),
      acceptance: s2,
      rating: { value: 0.75, note: "" },
      availability: { value: 1, note: "" },
      trustBadge: { value: 0.8, note: "" },
      multipliers: rules.multipliers.recommendation,
    });
    return { stage2: s2.score, final: final.score };
  };
  const yes = scoreFor("any");
  const unknown = scoreFor(null);
  const no = scoreFor("never");
  console.log(
    `      example (heavy rain, 6 km): yes ${yes.final} (stage 2 ${yes.stage2}) | ` +
      `not answered ${unknown.final} (${unknown.stage2}) | no ${no.final} (${no.stage2})`,
  );
  check("example: 'yes' ranks above not answered", yes.final > unknown.final);
  check("example: not answered ranks above 'no'", unknown.final > no.final);
}

// ------------------------------- Step 5: Previous Provider Priority (2026-11-22)
{
  const cand = (id: string, score: number, over: Record<string, unknown> = {}) => {
    const recommendation = { score, factors: [], signals: [], rules: [], reasons: [] };
    return {
      technician: { id, rating: 4.8, away_until: null, ...over },
      finalScore: score,
      recommendation,
      breakdown: { recommendation },
    } as any;
  };
  const historyWith = (id: string, rec: Record<string, unknown>) => ({
    pastJobs: 1,
    byTechnician: new Map([[id, { jobs: 1, completed: 1, stars: null, ...rec }]]),
  }) as any;
  const order = (list: any[]) => list.map((c) => c.technician.id).join(",");
  const ranked = [cand("a", 0.9), cand("b", 0.85), cand("c", 0.7)];

  const moved = applyPreviousTechnicianPriority(ranked, historyWith("c", {}));
  check("Step 5: the client's previous technician goes first", order(moved) === "c,a,b", order(moved));
  check("Step 5: their score is not changed", moved[0].finalScore === 0.7);
  check("Step 5: the reason says why they are first",
    moved[0].recommendation.reasons[0]?.code === "previous_technician" &&
      moved[0].breakdown.recommendation.previous_technician === true);
  check("Step 5: the others keep their order", order(moved.slice(1)) === "a,b");

  check("Step 5: a first-time client changes nothing",
    applyPreviousTechnicianPriority(ranked, { pastJobs: 0, byTechnician: new Map() } as any) === ranked);
  check("Step 5: a job never completed does not count",
    order(applyPreviousTechnicianPriority(ranked, historyWith("c", { completed: 0 }))) === "a,b,c");
  check("Step 5: rated 3 stars by this client - not pushed back at them",
    order(applyPreviousTechnicianPriority(ranked, historyWith("c", { stars: 3 }))) === "a,b,c");
  check("Step 5: rated 4 stars by this client - moved up",
    order(applyPreviousTechnicianPriority(ranked, historyWith("c", { stars: 4 })))[0] === "c");

  const lowRated = [cand("a", 0.9), cand("c", 0.7, { rating: 4.4 })];
  check("Step 5: an overall rating under 4.5 does not qualify",
    order(applyPreviousTechnicianPriority(lowRated, historyWith("c", {}))) === "a,c");
  const away = [cand("a", 0.9), cand("c", 0.7, { away_until: "2026-12-01" })];
  check("Step 5: on vacation - never put first",
    order(applyPreviousTechnicianPriority(away, historyWith("c", {}))) === "a,c");
  check("Step 5: not in today's pool - nothing to move",
    order(applyPreviousTechnicianPriority(ranked, historyWith("zz", {}))) === "a,b,c");
}

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
