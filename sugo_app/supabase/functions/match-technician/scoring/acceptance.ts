/**
 * Stage 2 - Acceptance.
 *
 * "Will this technician actually take this job, and turn up?"
 *
 * Stage 1 asked whether they *can* do it. A technician who is perfect on paper
 * but fully booked, 30 km away in a thunderstorm, and priced above the client's
 * ceiling is not a useful recommendation. Stage 2 is where the live context -
 * TomTom traffic, OpenWeatherMap conditions, workload, budget, urgency - turns
 * a qualified list into a realistic one.
 *
 * Every external input degrades safely: if TomTom or OpenWeatherMap is
 * unreachable, that factor is passed as null and `combine` redistributes its
 * weight instead of scoring everyone zero. See `weighting.ts`.
 */
import {
  ACCEPTANCE_WEIGHTS,
  BUDGET_OVERRUN_TOLERANCE,
  CLIENT_TRUST_SCORE,
  MAX_NO_SHOW_PENALTY,
  MAX_WORKLOAD,
  NO_SHOW_PENALTY,
  NEUTRAL_BUDGET_FIT,
  HARD_RADIUS_KM,
  SOFT_RADIUS_KM,
  TIER_HOURLY_RATE,
  TYPICAL_JOB_HOURS,
  URGENCY_PATH_SCORE,
} from "./constants.ts";
import { clamp01 } from "./geo.ts";
import { combine, type FactorInput } from "./weighting.ts";
import type {
  ClientTrust,
  JobContext,
  JobRow,
  StageResult,
  TechnicianRow,
} from "./types.ts";

/**
 * Client trust - how good a bet this client is for the technician.
 *
 * Stage 2 asks "will they actually take this job?", and part of that answer is
 * who is asking. A no-show costs the technician a round trip across the city
 * and an empty slot they could have sold, so a client with a record of turning
 * up is a better prospect than one with a record of not.
 *
 * ## Soft, never a block - and the floor is high on purpose
 *
 * Every client starts at `new`. A harsh penalty here would be a cold-start
 * trap on the client side: the people the platform most needs to attract would
 * be the hardest to match, and they would never get the completed jobs that
 * would raise their trust level. So `new` scores 0.70, not 0.
 *
 * With `client_trust` weighted at 0.10 of the stage, the worst case - a new
 * client with repeated no-shows - moves the final score by roughly two points
 * out of a hundred. Enough to break a tie between two equal technicians. Never
 * enough to leave someone unable to book.
 *
 * The remedy for a genuine repeat no-show is an account action taken by a
 * human, not a silent inability to find anyone.
 */
export function clientTrustScore(
  trust: ClientTrust,
): { value: number; note: string } {
  const base = CLIENT_TRUST_SCORE[trust.trustLevel] ?? CLIENT_TRUST_SCORE.new;

  // Capped, so the score can be dented but never floored.
  const penalty = Math.min(
    trust.noShowCount * NO_SHOW_PENALTY,
    MAX_NO_SHOW_PENALTY,
  );

  const value = clamp01(base - penalty);

  if (trust.noShowCount > 0) {
    return {
      value,
      note: `${trust.trustLevel} client with ${trust.noShowCount} recorded ` +
        `no-show${trust.noShowCount === 1 ? "" : "s"}`,
    };
  }

  const note = trust.trustLevel === "trusted"
    ? "Trusted client with a strong booking history"
    : trust.trustLevel === "verified"
    ? "ID-verified client"
    : "New client, no booking history yet";

  return { value, note };
}

/**
 * Budget fit.
 *
 * The quote is the technician's tier rate times a typical job length. If it
 * lands inside the client's range, full marks. Above the ceiling it decays
 * linearly to zero at `BUDGET_OVERRUN_TOLERANCE` times that ceiling. Coming in
 * under the client's floor is not penalised - a cheaper quote is good news.
 */
export function budgetFitScore(
  job: JobRow,
  technician: TechnicianRow,
): { value: number; note: string; quote: number } {
  const rate = TIER_HOURLY_RATE[technician.tier] ?? TIER_HOURLY_RATE.standard;
  const quote = rate * TYPICAL_JOB_HOURS;

  const ceiling = job.budget_max;
  if (ceiling === null || ceiling === undefined || ceiling <= 0) {
    return {
      value: NEUTRAL_BUDGET_FIT,
      note: `No budget set; indicative quote PHP ${quote}`,
      quote,
    };
  }

  if (quote <= ceiling) {
    return {
      value: 1,
      note: `Indicative PHP ${quote} fits a PHP ${Math.round(ceiling)} budget`,
      quote,
    };
  }

  const overrunLimit = ceiling * BUDGET_OVERRUN_TOLERANCE;
  const value = clamp01((overrunLimit - quote) / (overrunLimit - ceiling));

  return {
    value,
    note: `Indicative PHP ${quote} is above the PHP ${
      Math.round(ceiling)
    } ceiling`,
    quote,
  };
}

/**
 * Workload.
 *
 * Linear from 1 at an empty schedule to 0 at `MAX_WORKLOAD` active jobs. This
 * is the factor that makes ranking workload-aware: among technicians who score
 * alike on skill, the least busy one rises, so work spreads across the pool
 * instead of piling onto whoever happens to score highest.
 */
export function workloadScore(
  technician: TechnicianRow,
): { value: number; note: string; workload: number } {
  const workload = technician.current_workload ?? 0;
  const value = clamp01(1 - Math.min(workload, MAX_WORKLOAD) / MAX_WORKLOAD);

  const note = workload === 0
    ? "No active jobs, available today"
    : workload >= MAX_WORKLOAD
    ? `Fully booked with ${workload} active jobs`
    : `${workload} active job${workload === 1 ? "" : "s"} in progress`;

  return { value, note, workload };
}

/** Proximity, independent of traffic: linear from 1 at 0 km to 0 at the radius. */
export function proximityScore(
  distanceKm: number | null,
  serviceRadiusKm: number | null = null,
): { value: number | null; note: string } {
  if (distanceKm === null) {
    return { value: null, note: "Location unavailable" };
  }

  const label = distanceKm < 1
    ? `${Math.round(distanceKm * 1000)} m away`
    : `${distanceKm.toFixed(1)} km away`;

  // Inside the radius they declared, the old linear ramp over SOFT_RADIUS_KM.
  const within = clamp01(
    1 - Math.min(distanceKm, SOFT_RADIUS_KM) / SOFT_RADIUS_KM,
  );

  const radius = serviceRadiusKm ?? 0;
  if (radius <= 0 || distanceKm <= radius) {
    return { value: within, note: label };
  }

  // Past it, and this is the part that replaced a hard exclusion.
  //
  // A technician who wrote "10 km" has said they will not travel further, so
  // beyond it they are unlikely to accept - but "unlikely" is a score, not a
  // fact, and deleting them from the pool was emptying the Top 3 for clients
  // whose only nearby options were all slightly too far. It is the same
  // reasoning that turned `is_available` from a gate into a factor.
  //
  // The penalty is steep rather than token: the value decays across the gap
  // between their radius and the absolute ceiling, reaching zero at
  // HARD_RADIUS_KM. A technician 2 km past their limit is barely touched; one
  // at twice their limit is near the floor and will not reach a Top 3 that has
  // any closer candidate in it.
  const overshoot = distanceKm - radius;
  const headroom = Math.max(HARD_RADIUS_KM - radius, 1);
  const decay = clamp01(1 - overshoot / headroom);

  return {
    value: clamp01(within * decay),
    note: `${label}, past their ${radius.toFixed(0)} km service area`,
  };
}

/**
 * Traffic, scaled by how much the chosen path actually involves travel.
 *
 * A home service rides through the congestion; a shop pickup is one trip at a
 * time of the technician's choosing; an IT community job is remote. Without
 * that scaling, a jam would penalise every candidate identically and change
 * nothing about the ranking while making all the numbers look worse.
 */
export function trafficScore(
  context: JobContext,
): { value: number | null; note: string } {
  const traffic = context.traffic;
  if (!traffic.available || traffic.congestion === null) {
    return { value: null, note: "Traffic data unavailable" };
  }
  if (traffic.roadClosure) {
    return { value: 0, note: "Road closure reported at the job site" };
  }

  const value = clamp01(1 - traffic.congestion * context.travelExposure);
  return { value, note: traffic.label ?? "Traffic sampled at the job site" };
}

/** Weather, scaled by the same travel exposure as traffic. */
export function weatherScore(
  context: JobContext,
): { value: number | null; note: string } {
  const weather = context.weather;
  if (!weather.available || weather.severity === null) {
    return { value: null, note: "Weather data unavailable" };
  }

  const value = clamp01(1 - weather.severity * context.travelExposure);
  return { value, note: weather.label ?? "Conditions at the job site" };
}

/** Urgency crossed with the service path, straight from the lookup table. */
export function urgencyPathScore(
  job: JobRow,
  context: JobContext,
): { value: number; note: string } {
  const table = URGENCY_PATH_SCORE[job.urgency] ?? URGENCY_PATH_SCORE.can_wait;
  const value = table[context.servicePath] ?? 0.6;

  const note = job.urgency === "need_today"
    ? context.servicePath === "home_service"
      ? "Needed today and this is an on-site visit"
      : `Needed today, but a ${context.servicePath.replace("_", " ")} adds a leg`
    : "Client can wait, so timing is not decisive";

  return { value, note };
}

/**
 * `2026-09-27` -> `Sep 27`.
 *
 * The value is a calendar date with no time, so it is parsed and printed in
 * UTC: formatting it in any other zone can shift it a day either way.
 */
export function formatAwayUntil(isoDate: string): string {
  const date = new Date(`${isoDate}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return isoDate;
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  });
}

/**
 * Can the technician take this job, going by their own calendar?
 *
 * Decided by time off alone since 2026-09-22, when the online/offline switch
 * was removed from the app. The switch asked technicians to remember to flip
 * it many times a day, and one left off by accident kept a qualified person
 * at the bottom of every ranking with no one noticing. Vacation days are
 * planned once, end on their own, and are what a client actually needs to
 * know: whether this person can be booked.
 *
 * `technicians.is_available` still exists - the table is frozen - but nothing
 * reads it any more, so a value left over from the old switch cannot affect
 * a ranking.
 *
 * Binary on purpose. There is no honest middle value between "can be booked"
 * and "cannot", and inventing one would only blur the label on the card. A
 * technician on vacation stays in the pool and on the card, below anyone who
 * can take the job, and `job-response` refuses the booking.
 */
export function availabilityScore(
  technician: TechnicianRow,
): { value: number; note: string } {
  if (technician.away_until) {
    return {
      value: 0,
      note: `On vacation until ${formatAwayUntil(technician.away_until)}, so cannot be booked`,
    };
  }

  return { value: 1, note: "Taking jobs - no time off booked" };
}

/** Runs Stage 2 for one technician. */
export function scoreAcceptance(
  job: JobRow,
  technician: TechnicianRow,
  context: JobContext,
  distanceKm: number | null,
): { stage: StageResult; quote: number; workload: number } {
  const budget = budgetFitScore(job, technician);
  const workload = workloadScore(technician);
  const proximity = proximityScore(distanceKm, technician.service_radius_km);
  const traffic = trafficScore(context);
  const weather = weatherScore(context);
  const urgency = urgencyPathScore(job, context);

  const clientTrust = clientTrustScore(context.clientTrust);
  const availability = availabilityScore(technician);

  const inputs: FactorInput[] = [
    {
      key: "availability",
      label: "Online now",
      value: availability.value,
      weight: ACCEPTANCE_WEIGHTS.availability,
      note: availability.note,
    },
    {
      key: "budget_fit",
      label: "Budget fit",
      value: budget.value,
      weight: ACCEPTANCE_WEIGHTS.budget_fit,
      note: budget.note,
    },
    {
      key: "workload",
      // Renamed from "Availability": that word now belongs to the switch
      // above, and two factors sharing it made the breakdown unreadable.
      label: "Workload",
      value: workload.value,
      weight: ACCEPTANCE_WEIGHTS.workload,
      note: workload.note,
    },
    {
      key: "urgency_path",
      label: "Urgency fit",
      value: urgency.value,
      weight: ACCEPTANCE_WEIGHTS.urgency_path,
      note: urgency.note,
    },
    {
      key: "traffic",
      label: "Traffic",
      value: traffic.value,
      weight: ACCEPTANCE_WEIGHTS.traffic,
      note: traffic.note,
    },
    {
      key: "proximity",
      label: "Distance",
      value: proximity.value,
      weight: ACCEPTANCE_WEIGHTS.proximity,
      note: proximity.note,
    },
    {
      key: "weather",
      label: "Weather",
      value: weather.value,
      weight: ACCEPTANCE_WEIGHTS.weather,
      note: weather.note,
    },
    {
      // Who is asking. The lightest factor in the stage, deliberately: it
      // models a real cost to the technician without ever becoming the reason
      // a new client cannot get matched.
      key: "client_trust",
      label: "Client reliability",
      value: clientTrust.value,
      weight: ACCEPTANCE_WEIGHTS.client_trust,
      note: clientTrust.note,
    },
  ];

  return {
    stage: combine(inputs),
    quote: budget.quote,
    workload: workload.workload,
  };
}
