/**
 * Step 3 - rule-based weight selection.
 *
 * The factor weights in `constants.ts` are right for an ordinary request. They
 * are wrong for an unusual one: when a client needs someone today, in a
 * downpour, distance and "can they come now" matter far more than they do on
 * a dry afternoon for a repair that can wait. This module is where the
 * situation changes the weights.
 *
 * ## How it works
 *
 * 1. `deriveSignals` turns the job and the live context into a set of yes/no
 *    facts - urgent, rain, heavy traffic, on-site visit, appliance, technology.
 * 2. `selectRules` fires every rule in `MATCHING_RULES` whose conditions all
 *    hold, and composes their multipliers (capped at `MAX_RULE_MULTIPLIER`).
 * 3. `reweight` applies those multipliers to a stage's factors and
 *    renormalises, so the stage score is still a weighted mean on 0..1.
 *
 * ## Why multipliers, not replacement weight tables
 *
 * A rule says "distance matters MORE", not "distance is 27%". Multipliers
 * compose - urgent and rainy and congested can all fire at once - where
 * replacement tables would have to be written for every combination, and
 * would silently disagree with `constants.ts` the first time one was tuned.
 *
 * ## Fallback
 *
 * A signal whose data source is down is simply absent. TomTom unreachable
 * means no `heavy_traffic`, so the traffic rule does not fire and the base
 * weights stand - the distance factor still carries the ranking. Nothing here
 * ever throws for a missing input.
 *
 * Pure: no Deno APIs and no network, so `recommendation.test.ts` runs it
 * under plain Node.
 */
import {
  HEAVY_TRAFFIC_CONGESTION,
  MAX_RULE_MULTIPLIER,
  RAIN_SEVERITY,
} from "./constants.ts";
import { round } from "./weighting.ts";
import type {
  AppliedRule,
  ContextSignal,
  JobRow,
  MatchingRule,
  RuleSelection,
  RuleStage,
  ServicePath,
  StageResult,
  TrafficContext,
  WeatherContext,
  WeightMultipliers,
} from "./types.ts";

/**
 * The rule base, in the order it is printed in the demo view.
 *
 * Only signals the engine can actually measure appear here. The brief's own
 * example is "urgent + errand + rain"; SUGO has no errand category yet (jobs
 * are laptop, phone, appliance or network), so that rule is written as
 * "urgent + on-site visit + rain", which is the same situation for a repair.
 * Likewise there is no data on a technician's equipment or rain gear, so no
 * rule pretends to weigh either.
 */
export const MATCHING_RULES: MatchingRule[] = [
  {
    id: "urgent_visit_in_rain",
    label: "Urgent visit in the rain",
    rationale:
      "Someone has to travel today through bad weather. A short trip by a " +
      "technician who is free now is worth more than a slightly better " +
      "specialist across the city.",
    when: ["urgent", "rain", "on_site"],
    adjust: {
      acceptance: { proximity: 1.6, availability: 1.4, weather: 1.5 },
      recommendation: { context_fit: 1.5, acceptance: 1.2 },
    },
  },
  {
    id: "heavy_traffic_visit",
    label: "Heavy traffic on the way",
    rationale:
      "Congestion multiplies every kilometre. Travel time and distance decide " +
      "more of who can realistically arrive.",
    when: ["heavy_traffic", "on_site"],
    adjust: {
      acceptance: { proximity: 1.5, traffic: 1.5, availability: 1.2 },
      recommendation: { context_fit: 1.3 },
    },
  },
  {
    id: "urgent_request",
    label: "Needed today",
    rationale:
      "The client cannot wait, so a technician who is free today and not " +
      "already buried in jobs is more useful than one who will get to it later.",
    when: ["urgent"],
    adjust: {
      acceptance: { availability: 1.3, workload: 1.4, urgency_path: 1.2 },
    },
  },
  {
    id: "appliance_repair",
    label: "Appliance repair",
    rationale:
      "Appliance faults are specialist work - compressors, boards, motors. " +
      "Proven skill on this kind of machine and a record of correct " +
      "diagnoses matter more than they do for a quick phone fix.",
    when: ["appliance"],
    adjust: {
      suitability: {
        specialization: 1.3,
        skill_tag: 1.2,
        tier: 1.2,
        diagnosis_accuracy: 1.2,
      },
    },
  },
];

/**
 * `on_site` means a technician comes to the client's door. A shop pickup is
 * one trip at a time the technician picks, and an IT-community job is remote;
 * Stage 2's travel exposure already scales weather and traffic for both, so
 * the travel rules are kept for the case where the trip is the job.
 */
const ON_SITE_PATHS: ServicePath[] = ["home_service"];

/**
 * The conditions that hold for this job.
 *
 * Only what the engine can measure. Weather and traffic contribute nothing
 * when their API was unavailable - absent, not "fine".
 */
export function deriveSignals(
  job: JobRow,
  servicePath: ServicePath,
  traffic: TrafficContext,
  weather: WeatherContext,
): ContextSignal[] {
  const signals: ContextSignal[] = [];

  if (job.urgency === "need_today") signals.push("urgent");

  if (
    weather.available && weather.severity !== null &&
    weather.severity >= RAIN_SEVERITY
  ) {
    signals.push("rain");
  }

  if (
    traffic.available &&
    (traffic.roadClosure ||
      (traffic.congestion !== null &&
        traffic.congestion >= HEAVY_TRAFFIC_CONGESTION))
  ) {
    signals.push("heavy_traffic");
  }

  if (ON_SITE_PATHS.includes(servicePath)) signals.push("on_site");

  if (job.device_type === "appliance") {
    signals.push("appliance");
  } else {
    signals.push("technology");
  }

  return signals;
}

/**
 * Fires every rule whose conditions all hold and composes their effects.
 *
 * Multipliers on the same factor multiply together, then are capped at
 * `MAX_RULE_MULTIPLIER`, so stacked rules can sharpen the ranking but never
 * collapse it onto a single factor.
 */
export function selectRules(
  signals: ContextSignal[],
  rules: MatchingRule[] = MATCHING_RULES,
): RuleSelection {
  const held = new Set(signals);
  const multipliers: Record<RuleStage, WeightMultipliers> = {
    suitability: {},
    acceptance: {},
    recommendation: {},
  };
  const applied: AppliedRule[] = [];

  for (const rule of rules) {
    if (!rule.when.every((signal) => held.has(signal))) continue;

    const effects: AppliedRule["effects"] = [];
    for (const stage of Object.keys(rule.adjust) as RuleStage[]) {
      for (const [factor, multiplier] of Object.entries(rule.adjust[stage]!)) {
        const composed = (multipliers[stage][factor] ?? 1) * multiplier;
        multipliers[stage][factor] = Math.min(composed, MAX_RULE_MULTIPLIER);
        effects.push({ stage, factor, multiplier });
      }
    }

    applied.push({
      id: rule.id,
      label: rule.label,
      rationale: rule.rationale,
      when: rule.when,
      effects,
    });
  }

  return { signals, applied, multipliers };
}

/**
 * Applies rule multipliers to a stage that `combine` already scored.
 *
 * Each factor's weight becomes `weight x multiplier`, then all weights are
 * renormalised to sum to 1 again - so the stage score stays a weighted mean on
 * 0..1 and stays comparable with a job where no rule fired. Factors the rules
 * do not mention keep their share of what is left.
 *
 * `additiveKeys` are entries that are not weighted factors at all - Stage 1's
 * cold-start boost, which is added on top of the mean. They are carried
 * through unchanged and added back after the re-weighted mean.
 */
export function reweight(
  stage: StageResult,
  multipliers: WeightMultipliers,
  additiveKeys: string[] = ["cold_start"],
): StageResult {
  const additive = stage.factors.filter((f) => additiveKeys.includes(f.key));
  const weighted = stage.factors.filter((f) => !additiveKeys.includes(f.key));

  const touched = weighted.some((f) => (multipliers[f.key] ?? 1) !== 1);
  if (!touched || weighted.length === 0) return stage;

  const raw = weighted.map((f) => f.weight * (multipliers[f.key] ?? 1));
  const total = raw.reduce((sum, w) => sum + w, 0);
  if (total <= 0) return stage;

  const factors = weighted.map((f, i) => {
    const weight = raw[i] / total;
    const changed = (multipliers[f.key] ?? 1) !== 1 ||
      Math.abs(weight - f.weight) > 1e-4;
    return {
      ...f,
      weight: round(weight),
      contribution: round(f.value * weight),
      ...(changed ? { base_weight: f.weight } : {}),
    };
  });

  const mean = factors.reduce((sum, f) => sum + f.contribution, 0);
  const boost = additive.reduce((sum, f) => sum + f.contribution, 0);

  return {
    score: round(Math.min(Math.max(mean + boost, 0), 1)),
    factors: [...factors, ...additive],
  };
}
