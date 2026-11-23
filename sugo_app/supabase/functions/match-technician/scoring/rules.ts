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
 *    facts - urgent, rain, heavy rain, heavy traffic, on-site visit,
 *    appliance, technology.
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
 * weights stand - travel burden still carries the ranking, at a typical city
 * speed. Nothing here ever throws for a missing input.
 *
 * ## Since 2026-11-22
 *
 * The rules name the Table 10 and Table 11 keys. Availability is a Table 10
 * criterion now, so the rules that boost it act on the final score
 * (`recommendation`) rather than on Stage 2. Urgency is no longer a Stage 2
 * signal of its own; the "Needed today" rule is how it shapes the ranking.
 *
 * Pure: no Deno APIs and no network, so `recommendation.test.ts` runs it
 * under plain Node.
 */
import {
  HEAVY_RAIN_SEVERITY,
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
      acceptance: { travel_burden: 1.6, conditions_readiness: 1.5 },
      recommendation: { acceptance: 1.3, availability: 1.4 },
    },
  },
  {
    // Added 2026-11-22. Before this, rain only moved the ranking when the job
    // was also urgent; a can-wait home visit in a downpour was ranked as on a
    // dry day apart from the light weather-readiness signal.
    id: "rain_visit",
    label: "Rain on the way",
    rationale:
      "Someone has to ride to the client through the rain. A shorter trip " +
      "means less time on wet roads and less chance of a late arrival.",
    when: ["rain", "on_site"],
    adjust: {
      acceptance: { travel_burden: 1.3, conditions_readiness: 1.5 },
    },
  },
  {
    // Fires ON TOP of "Rain on the way" (a heavy-rain job holds both signals),
    // so its multipliers are the extra a downpour adds over ordinary rain:
    // travel burden 1.3 x 1.3 = 1.69, weather readiness 1.5 x 1.3 = 1.95.
    id: "heavy_rain_visit",
    label: "Heavy rain or thunderstorm",
    rationale:
      "In a downpour or a storm a long ride is slow and unsafe, and the " +
      "technician most likely to arrive is the one closest to the client.",
    when: ["heavy_rain", "on_site"],
    adjust: {
      acceptance: { travel_burden: 1.3, conditions_readiness: 1.3 },
      recommendation: { acceptance: 1.2 },
    },
  },
  {
    id: "heavy_traffic_visit",
    label: "Heavy traffic on the way",
    rationale:
      "Congestion multiplies every kilometre. Travel time, and whether the " +
      "technician said they still go in heavy traffic, decide more of who " +
      "can realistically arrive.",
    when: ["heavy_traffic", "on_site"],
    adjust: {
      // Readiness added 2026-11-22: the technician's own "do you still go in
      // heavy traffic?" answer counts more while the traffic is heavy.
      acceptance: { travel_burden: 1.5, conditions_readiness: 1.5 },
      recommendation: { acceptance: 1.2, availability: 1.2 },
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
      acceptance: { workload: 1.4 },
      recommendation: { availability: 1.3 },
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
 * Stage 2's travel exposure already scales travel burden and weather
 * readiness for both, so the travel rules are kept for the case where the
 * trip is the job.
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
    // Heavy rain is a stronger kind of rain, never instead of it.
    if (weather.severity >= HEAVY_RAIN_SEVERITY) signals.push("heavy_rain");
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
