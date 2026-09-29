/**
 * "Why this technician?" - the reasons a client reads.
 *
 * Every reason is gated on a recorded number crossing a stated threshold, and
 * quotes that number. None is copywriting: if the data does not support a
 * sentence, the sentence is not produced. A technician with nothing notable
 * about them gets a short list, which is the honest answer.
 *
 * Positives come first, strongest evidence first. Caveats follow - the
 * vacation, the distance past their own radius, the price above budget - so a
 * recommendation never hides the one thing that would change the client's mind.
 *
 * Pure: no Deno APIs, no network.
 */
import type {
  AccuracyStats,
  ClientTechnicianHistory,
  ContextSignal,
  JobRow,
  RecommendationReason,
  ScoreFactor,
  StageResult,
  TechnicianRow,
} from "./types.ts";
import { formatAwayUntil } from "./acceptance.ts";

/** Within this, "near you" is worth saying. */
const NEAR_KM = 5;

/** A travel time short enough to say it beats the traffic. */
const QUICK_ETA_MINUTES = 20;

/** Ratings below this many jobs are not quoted - too little behind them. */
const RATING_MIN_JOBS = 5;
const QUOTABLE_RATING = 4.5;

/** Offers answered before a response rate is worth quoting. */
const RESPONSE_MIN_ANSWERED = 3;
const QUOTABLE_RESPONSE = 0.8;

/** Stage 1 specialisation values, from `SPECIALIZATION_MATCH`. */
const ASSESSED_ON_BRAND = 0.85;
const ASSESSED_ON_DEVICE = 0.6;

const DEVICE_WORDS: Record<string, string> = {
  laptop: "laptops",
  phone: "phones",
  appliance: "appliances",
  network: "network devices",
};

function factor(stage: StageResult, key: string): ScoreFactor | undefined {
  return stage.factors.find((f) => f.key === key);
}

function distanceText(km: number): string {
  return km < 1 ? `${Math.round(km * 1000)} m` : `${km.toFixed(1)} km`;
}

function peso(amount: number): string {
  return `₱${Math.round(amount).toLocaleString("en-US")}`;
}

export function buildReasons(input: {
  job: JobRow;
  technician: TechnicianRow;
  suitability: StageResult;
  acceptance: StageResult;
  accuracy: AccuracyStats;
  signals: ContextSignal[];
  distanceKm: number | null;
  etaMinutes: number | null;
  workload: number;
  coldStart: boolean;
  quote: number;
  history: ClientTechnicianHistory | undefined;
  responseRate: number;
  answeredOffers: number;
}): RecommendationReason[] {
  const { job, technician } = input;
  const held = new Set(input.signals);
  const positives: RecommendationReason[] = [];
  const caveats: RecommendationReason[] = [];
  const device = DEVICE_WORDS[job.device_type] ?? job.device_type;

  // ------------------------------------------------------- can do the job
  const specialization = factor(input.suitability, "specialization")?.value ?? 0;
  const brand = job.brand && job.brand.toLowerCase() !== "others" ? job.brand : null;

  if (specialization >= ASSESSED_ON_BRAND && brand) {
    positives.push({
      code: "assessed_brand",
      text: `Passed SUGO's assessment on ${brand} ${device}`,
      kind: "positive",
    });
  } else if (specialization >= ASSESSED_ON_DEVICE) {
    positives.push({
      code: "assessed_device",
      text: `Passed SUGO's assessment on ${device}`,
      kind: "positive",
    });
  } else if (specialization > 0.2) {
    caveats.push({
      code: "unassessed",
      text: `Lists ${device} repair, but has not been assessed on it yet`,
      kind: "caveat",
    });
  }

  if (input.accuracy.similarRepairs > 0) {
    const n = input.accuracy.similarRepairs;
    positives.push({
      code: "similar_repairs",
      text: `${n} similar repair${n === 1 ? "" : "s"} done through SUGO`,
      kind: "positive",
    });
  } else if ((technician.total_jobs ?? 0) >= RATING_MIN_JOBS) {
    positives.push({
      code: "experience",
      text: `${technician.total_jobs} jobs completed through SUGO`,
      kind: "positive",
    });
  } else if (input.coldStart) {
    positives.push({
      code: "newly_verified",
      text: "Newly verified - ID checked and approved by SUGO",
      kind: "positive",
    });
  }

  const rating = technician.rating ?? 0;
  if (rating >= QUOTABLE_RATING && (technician.total_jobs ?? 0) >= RATING_MIN_JOBS) {
    positives.push({
      code: "rating",
      text: `Rated ${rating.toFixed(1)} by past clients`,
      kind: "positive",
    });
  }

  // --------------------------------------------------- your own history
  const stars = input.history?.stars ?? null;
  if (stars !== null && stars >= 4) {
    positives.push({
      code: "rated_by_you",
      text: `You rated them ${stars} stars last time`,
      kind: "positive",
    });
  } else if (stars !== null && stars <= 2) {
    caveats.push({
      code: "rated_low_by_you",
      text: `You rated them ${stars} star${stars === 1 ? "" : "s"} last time`,
      kind: "caveat",
    });
  } else if ((input.history?.jobs ?? 0) > 0) {
    positives.push({
      code: "worked_before",
      text: "Has worked on a job for you before",
      kind: "positive",
    });
  }

  // ---------------------------------------------------- situation fit
  if (input.distanceKm !== null && input.distanceKm <= NEAR_KM) {
    positives.push({
      code: "near",
      text: `${distanceText(input.distanceKm)} from your location`,
      kind: "positive",
    });
  }

  if (
    held.has("heavy_traffic") && held.has("on_site") &&
    input.etaMinutes !== null && input.etaMinutes <= QUICK_ETA_MINUTES
  ) {
    positives.push({
      code: "beats_traffic",
      text: `About ${Math.max(1, Math.round(input.etaMinutes))} min away, even in today's traffic`,
      kind: "positive",
    });
  }

  if (
    held.has("rain") && held.has("on_site") &&
    input.distanceKm !== null && input.distanceKm <= NEAR_KM
  ) {
    positives.push({
      code: "short_trip_rain",
      text: "A short trip for them in the current rain",
      kind: "positive",
    });
  }

  if (technician.away_until) {
    caveats.push({
      code: "on_vacation",
      text: `On vacation until ${formatAwayUntil(technician.away_until)} - cannot be booked`,
      kind: "caveat",
    });
  } else if (input.workload === 0) {
    positives.push({
      code: "free_now",
      text: held.has("urgent")
        ? "Free to take an urgent job today"
        : "No other jobs in progress",
      kind: "positive",
    });
  } else if (input.workload <= 2) {
    positives.push({
      code: "light_schedule",
      text: "Light schedule today",
      kind: "positive",
    });
  }

  const radius = technician.service_radius_km ?? 0;
  if (input.distanceKm !== null && radius > 0 && input.distanceKm > radius) {
    caveats.push({
      code: "outside_area",
      text: `Outside their usual ${radius.toFixed(0)} km service area`,
      kind: "caveat",
    });
  }

  // ------------------------------------------------------------ price
  const budget = job.budget_max;
  if (budget !== null && budget > 0) {
    if (input.quote <= budget) {
      positives.push({
        code: "budget_fit",
        text: `Typical rate fits your ${peso(budget)} budget`,
        kind: "positive",
      });
    } else {
      caveats.push({
        code: "over_budget",
        text: `Typical rate (about ${peso(input.quote)}) is above your ${peso(budget)} budget`,
        kind: "caveat",
      });
    }
  }

  // ------------------------------------------------------ reliability
  if (
    input.answeredOffers >= RESPONSE_MIN_ANSWERED &&
    input.responseRate >= QUOTABLE_RESPONSE
  ) {
    positives.push({
      code: "responsive",
      text: "Usually accepts the jobs they are offered",
      kind: "positive",
    });
  }

  return [...positives, ...caveats];
}
