/**
 * Rule-based weighting, Stage 3 recommendation and the client-facing reasons,
 * all pinned.
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
import {
  clientPreferenceScore,
  contextFitScore,
  performanceScore,
  scoreRecommendation,
} from "./recommendation.ts";
import { buildReasons } from "./reasons.ts";
import { combine } from "./weighting.ts";
import type { ClientHistory, StageResult } from "./types.ts";

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
    near(sel.multipliers.acceptance.availability, 1.82),
    String(sel.multipliers.acceptance.availability));

  const stacked = selectRules(["urgent"], [
    { id: "a", label: "a", rationale: "", when: ["urgent"], adjust: { acceptance: { proximity: 1.8 } } },
    { id: "b", label: "b", rationale: "", when: ["urgent"], adjust: { acceptance: { proximity: 1.8 } } },
  ]);
  check("stacked rules are capped at 2.0",
    stacked.multipliers.acceptance.proximity === 2,
    String(stacked.multipliers.acceptance.proximity));

  const calm = selectRules(["technology"]);
  check("an ordinary request fires no rule", calm.applied.length === 0);

  check("every rule's conditions are real signals",
    MATCHING_RULES.every((r) => r.when.every((w) =>
      ["urgent", "rain", "heavy_traffic", "on_site", "appliance", "technology"]
        .includes(w))));
}

// --------------------------------------------------------- reweighting maths
const acceptanceFor = (proximity: number, availability: number): StageResult =>
  combine([
    { key: "availability", label: "", value: availability, weight: 0.18 },
    { key: "budget_fit", label: "", value: 0.7, weight: 0.15 },
    { key: "workload", label: "", value: 1, weight: 0.15 },
    { key: "proximity", label: "", value: proximity, weight: 0.18 },
    { key: "weather", label: "", value: 0.5, weight: 0.06 },
  ]);

{
  const stage = acceptanceFor(0.9, 1);
  const rain = selectRules(["urgent", "rain", "on_site"]).multipliers.acceptance;
  const out = reweight(stage, rain);
  const sum = out.factors.reduce((s, f) => s + f.weight, 0);
  check("re-weighted weights still sum to 1", near(sum, 1), sum.toFixed(4));
  check("a boosted factor carries its base weight for the demo view",
    out.factors.find((f) => f.key === "proximity")!.base_weight !== undefined);
  check("no multipliers returns the stage untouched", reweight(stage, {}) === stage);

  // The point of the rule: in the rain, the near technician gains on the far one.
  const nearTech = acceptanceFor(0.9, 1);
  const farTech = acceptanceFor(0.2, 1);
  const gapBefore = nearTech.score - farTech.score;
  const gapAfter = reweight(nearTech, rain).score - reweight(farTech, rain).score;
  check("rain + urgency widens the lead of the nearer technician",
    gapAfter > gapBefore, `${gapBefore.toFixed(3)} -> ${gapAfter.toFixed(3)}`);

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

// ------------------------------------------------------ Stage 3 components
const noHistory: ClientHistory = { pastJobs: 0, byTechnician: new Map() };
const history: ClientHistory = {
  pastJobs: 3,
  byTechnician: new Map([
    ["liked", { jobs: 1, completed: 1, stars: 5 }],
    ["disliked", { jobs: 1, completed: 1, stars: 2 }],
    ["unrated", { jobs: 1, completed: 1, stars: null }],
  ]),
};

check("a first-time client has no preference score (cold start)",
  clientPreferenceScore(noHistory, "t").value === null);
check("rated well before scores 1.0", clientPreferenceScore(history, "liked").value === 1);
check("rated poorly before scores 0.1", clientPreferenceScore(history, "disliked").value === 0.1);
check("worked together, unrated, scores 0.75", clientPreferenceScore(history, "unrated").value === 0.75);
check("never booked, client has history, scores 0.5", clientPreferenceScore(history, "t").value === 0.5);

{
  const fresh = performanceScore(undefined, 0);
  check("no offers answered sits at the 0.75 response prior",
    near(fresh.responseRate, 0.75), String(fresh.responseRate));
  check("reliable responder rises above the prior",
    performanceScore({ accepted: 10, declined: 0 }, 20).responseRate > 0.75);
  check("serial decliner falls below the prior",
    performanceScore({ accepted: 0, declined: 5 }, 20).responseRate < 0.75);
  check("experience grows with completed jobs",
    performanceScore(undefined, 50).value > performanceScore(undefined, 2).value);
}

{
  const base = {
    signals: ["urgent", "on_site"] as any, distanceKm: 3, serviceRadiusKm: 10,
    etaMinutes: 9, workload: 0,
  };
  const free = contextFitScore({ ...base, onVacation: false }).value!;
  const away = contextFitScore({ ...base, onVacation: true }).value!;
  check("urgent: a technician on vacation fits the moment worse", free > away,
    `${free.toFixed(3)} > ${away.toFixed(3)}`);
  check("remote job that can wait, no radius: context fit is not invented",
    contextFitScore({
      signals: ["technology"], distanceKm: null, serviceRadiusKm: null,
      etaMinutes: null, onVacation: false, workload: 0,
    }).value === null);
}

// ----------------------------------------------------- Stage 3 combination
const stage = (score: number): StageResult => ({ score, factors: [] });
const rec = (s1: number, s2: number, pref: number | null) =>
  scoreRecommendation({
    suitability: stage(s1),
    acceptance: stage(s2),
    contextFit: { value: 0.7, note: "" },
    clientPreference: { value: pref, note: "" },
    performance: { value: 0.6, note: "" },
    multipliers: {},
  });

{
  const cold = rec(0.8, 0.7, null);
  check("cold-start client: preference factor is dropped, not zeroed",
    !cold.factors.some((f) => f.key === "client_preference"));
  const sum = cold.factors.reduce((s, f) => s + f.weight, 0);
  check("...and its weight is shared out (weights sum to 1)", near(sum, 1), sum.toFixed(4));
  check("the recommendation score is not a copy of suitability",
    Math.abs(cold.score - 0.8) > 0.01, cold.score.toFixed(3));
  check("can-do-the-job outranks merely-available (0.9/0.5 vs 0.5/0.9)",
    rec(0.9, 0.5, null).score > rec(0.5, 0.9, null).score);
  check("a client's 5-star history lifts the same technician",
    rec(0.8, 0.7, 1).score > rec(0.8, 0.7, 0.5).score);
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
  quote: 1050,
  history: undefined,
  responseRate: 0.75,
  answeredOffers: 0,
  ...over,
});
const codes = (r: { code: string }[]) => r.map((x) => x.code);

check("no budget given: no budget reason is claimed",
  !codes(reasonsFor({})).some((c) => c.startsWith("budget") || c === "over_budget"));
check("budget fits: the reason quotes the client's budget",
  reasonsFor({ job: job({ budget_max: 1500 }) }).some((r) => r.code === "budget_fit" && r.text.includes("₱1,500")));
check("over budget is a caveat, not hidden",
  reasonsFor({ job: job({ budget_max: 500 }) }).some((r) => r.code === "over_budget" && r.kind === "caveat"));
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
check("positives are listed before caveats", (() => {
  const r = reasonsFor({ job: job({ budget_max: 500 }) });
  const firstCaveat = r.findIndex((x) => x.kind === "caveat");
  return firstCaveat === -1 || r.slice(firstCaveat).every((x) => x.kind === "caveat");
})());

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
