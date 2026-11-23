/**
 * Stage 2 - Acceptance likelihood (Table 11).
 *
 * "Will this technician actually take this job, and turn up?"
 *
 * Stage 1 asked whether they *can* do it. A technician who is perfect on paper
 * but fully booked, an hour away in a thunderstorm, and being offered less than
 * they usually take is not a useful recommendation. Stage 2 is where the live
 * context - TomTom traffic, OpenWeatherMap conditions, workload, the fixed
 * price - turns a qualified list into a realistic one.
 *
 * | Signal            | Weight | What it assesses                                   |
 * |-------------------|--------|----------------------------------------------------|
 * | Travel burden     | 0.30   | Traffic-adjusted travel time to the task location  |
 * | Current workload  | 0.25   | How many active bookings they already hold         |
 * | Price fit         | 0.20   | Whether the task's fixed price meets their rate    |
 * | Coverage fit      | 0.15   | Whether the task is inside their service area      |
 * | Weather & traffic readiness | 0.10 | Whether they will travel in the current rain and traffic |
 *
 * Every signal is per technician: two candidates for the same job get
 * different values, so every row can change who ranks first.
 *
 * Every external input degrades safely: if a value cannot be measured, the
 * signal is passed as null and `combine` redistributes its weight instead of
 * scoring everyone zero. See `weighting.ts`.
 */
import {
  ACCEPTANCE_WEIGHTS,
  HARD_RADIUS_KM,
  HEAVY_RAIN_SEVERITY,
  HEAVY_TRAFFIC_CONGESTION,
  MAX_WORKLOAD,
  NEUTRAL_PRICE_FIT,
  PRICE_FIT_MIN_PHP,
  PRICE_FIT_ZERO_RATIO,
  RAIN_SEVERITY,
  RAIN_TRAVEL_READINESS,
  TRAVEL_BURDEN_MAX_MINUTES,
} from "./constants.ts";
import { fixedJobPrice } from "../../_shared/labor_price.ts";
import { clamp01, travelMinutes } from "./geo.ts";
import { combine, type FactorInput } from "./weighting.ts";
import type {
  JobContext,
  JobRow,
  StageResult,
  TechnicianRow,
} from "./types.ts";

function peso(amount: number): string {
  return `₱${Math.round(amount).toLocaleString("en-US")}`;
}

function minutesText(minutes: number): string {
  return `${Math.max(1, Math.round(minutes))} min`;
}

/**
 * Travel burden: traffic-adjusted travel time to the task location.
 *
 * Distance from the technician's base, at the live TomTom speed sampled at the
 * job site (`travelMinutes`; a typical city speed when TomTom is down). Linear
 * from 1 at the door to 0 at `TRAVEL_BURDEN_MAX_MINUTES`, scaled by how much
 * the service path actually involves travel: a home visit rides the whole way,
 * a remote IT job barely travels at all.
 *
 * This one signal replaced the old separate Distance and Traffic factors.
 * Traffic on its own was sampled once per job, so it was the same number for
 * every candidate; multiplied into each technician's own distance, it now
 * makes the far technician pay more for a jam than the near one.
 */
export function travelBurdenScore(
  etaMinutes: number | null,
  travelExposure: number,
  trafficAvailable: boolean,
): { value: number | null; note: string } {
  if (etaMinutes === null) {
    return { value: null, note: "Location unavailable" };
  }

  const share = Math.min(etaMinutes, TRAVEL_BURDEN_MAX_MINUTES) /
    TRAVEL_BURDEN_MAX_MINUTES;
  const value = clamp01(1 - share * travelExposure);

  const note = trafficAvailable
    ? `About ${minutesText(etaMinutes)} away at current traffic`
    : `About ${minutesText(etaMinutes)} away (traffic data unavailable)`;

  return { value, note };
}

/**
 * Current workload.
 *
 * Linear from 1 at an empty schedule to 0 at `MAX_WORKLOAD` active jobs. This
 * is the signal that makes ranking workload-aware: among technicians who score
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

/**
 * Price fit: whether the task's fixed price meets the technician's rate.
 *
 * Replaced Budget fit on 2026-11-22. The client used to type a budget and the
 * engine compared it with the technician's tier rate; SUGO now quotes one
 * fixed price per symptom, so there is no budget to compare. The question
 * this stage asks - will they take it? - became: is this price worth this
 * technician's time?
 *
 * The price is the labor fee plus the 20% urgent fee when the job is needed
 * today (`fixedJobPrice`). The travel or delivery fee is left out: it pays for
 * the trip, which Travel burden already scores.
 *
 * At or above the tier's minimum (`PRICE_FIT_MIN_PHP`), full marks. Below it,
 * linear down to 0 at `PRICE_FIT_ZERO_RATIO` of the minimum. A symptom with no
 * single price scores the neutral `NEUTRAL_PRICE_FIT`.
 */
export function priceFitScore(
  job: JobRow,
  technician: TechnicianRow,
): { value: number; note: string; pricePhp: number | null } {
  const tier = technician.tier in PRICE_FIT_MIN_PHP ? technician.tier : "standard";
  const minimum = PRICE_FIT_MIN_PHP[tier];
  const price = fixedJobPrice(job.problem_symptom, job.urgency);

  if (price === null) {
    return {
      value: NEUTRAL_PRICE_FIT,
      note: "No single fixed price for this job yet",
      pricePhp: null,
    };
  }

  if (price >= minimum) {
    return {
      value: 1,
      note: `Fixed price ${peso(price)} meets the ${peso(minimum)} ${tier} minimum`,
      pricePhp: price,
    };
  }

  const ratio = price / minimum;
  const value = clamp01(
    (ratio - PRICE_FIT_ZERO_RATIO) / (1 - PRICE_FIT_ZERO_RATIO),
  );

  return {
    value,
    note: `Fixed price ${peso(price)} is below the ${peso(minimum)} ${tier} minimum`,
    pricePhp: price,
  };
}

/**
 * Coverage fit: whether the task falls within the technician's service area.
 *
 * Inside the radius they declared, full marks. Past it, the value decays
 * across the gap between their radius and `HARD_RADIUS_KM`, reaching 0 there.
 * A technician 2 km past their limit is barely touched; one at twice their
 * limit is near the floor and will not reach a Top 3 that has any closer
 * candidate in it.
 *
 * A penalty, not an exclusion. Deleting everyone past their radius was
 * emptying the Top 3 for clients whose only nearby options were all slightly
 * too far - "unlikely to accept" is a score, not a fact.
 *
 * Null when the distance or the radius is unknown, so the weight goes to the
 * other signals rather than guessing.
 */
export function coverageFitScore(
  distanceKm: number | null,
  serviceRadiusKm: number | null,
): { value: number | null; note: string } {
  const radius = serviceRadiusKm ?? 0;
  if (distanceKm === null) {
    return { value: null, note: "Location unavailable" };
  }
  if (radius <= 0) {
    return { value: null, note: "No service area declared" };
  }

  if (distanceKm <= radius) {
    return {
      value: 1,
      note: `Inside their ${radius.toFixed(0)} km service area`,
    };
  }

  const overshoot = distanceKm - radius;
  const headroom = Math.max(HARD_RADIUS_KM - radius, 1);
  const value = clamp01(1 - overshoot / headroom);

  return {
    value,
    note: `${overshoot.toFixed(1)} km past their ${radius.toFixed(0)} km service area`,
  };
}

/**
 * Weather & traffic readiness: will the technician actually travel to the
 * task in the current rain and traffic? (Was "Weather readiness" until
 * 2026-11-22.)
 *
 * Since 20261122000001 registration asks every technician two questions -
 * will you travel in the rain (any / not in heavy rain / never), and in
 * heavy traffic (yes / no). This signal is the lower of two parts:
 *
 * **Rain part.** While it is raining at the job (`RAIN_SEVERITY`), a
 * technician who answered is scored on their answer (`RAIN_TRAVEL_READINESS`:
 * 1 if they said they go, 0 if not; "not in heavy rain" is 1 in rain and 0
 * in heavy rain or a storm). With no rain, or no answer, it is estimated as
 * before: `1 - severity x exposure x share of a full trip`.
 *
 * **Traffic part.** Counted only while the traffic is heavy
 * (`HEAVY_TRAFFIC_CONGESTION`, or a road closure). An answer scores 1 or 0;
 * no answer is estimated the same way, from the congestion and their trip.
 *
 * The LOWER of the two is the value, because a technician who will go in the
 * rain but not in heavy traffic is not going today either way.
 *
 * Every answer is scaled by the path's travel exposure: `1 - exposure x
 * (1 - answer)`. A home visit takes the answer whole; a shop pickup (0.6)
 * takes most of it; a remote job barely any.
 *
 * So, in the rain: said yes (1.0) > not answered (an estimate) > said no
 * (0.0). Answering "yes" is what lifts a technician who will really go above
 * one nobody knows about. A "no" is a score, never a removal - the only
 * expert on a client's machine is still shown, with the reason.
 */
export function conditionsReadinessScore(
  technician: TechnicianRow,
  context: JobContext,
  etaMinutes: number | null,
): { value: number | null; note: string } {
  const exposure = context.travelExposure;
  const share = etaMinutes === null
    ? 1
    : Math.min(etaMinutes, TRAVEL_BURDEN_MAX_MINUTES) / TRAVEL_BURDEN_MAX_MINUTES;
  const fromAnswer = (answer: number) => clamp01(1 - exposure * (1 - answer));

  const parts: number[] = [];
  const notes: string[] = [];

  // ------------------------------------------------------------ rain part
  const weather = context.weather;
  if (weather.available && weather.severity !== null) {
    const raining = weather.severity >= RAIN_SEVERITY;
    const heavy = weather.severity >= HEAVY_RAIN_SEVERITY;
    const answer = technician.rain_travel
      ? RAIN_TRAVEL_READINESS[technician.rain_travel]
      : undefined;
    const label = weather.label ?? "Conditions at the job site";

    if (raining && answer) {
      const ready = heavy ? answer.heavyRain : answer.rain;
      parts.push(fromAnswer(ready));
      notes.push(
        ready === 1
          ? (heavy
            ? "Said they travel even in heavy rain"
            : "Said they travel in the rain")
          : (heavy
            ? "Said they do not travel in heavy rain"
            : "Said they do not travel in the rain"),
      );
    } else {
      parts.push(clamp01(1 - weather.severity * exposure * share));
      notes.push(
        raining
          ? `${label}, ${etaMinutes === null ? "trip time unknown" : `${minutesText(etaMinutes)} trip`} (no answer on rain yet)`
          : label,
      );
    }
  }

  // --------------------------------------------------------- traffic part
  const traffic = context.traffic;
  const heavyTraffic = traffic.available &&
    (traffic.roadClosure ||
      (traffic.congestion !== null &&
        traffic.congestion >= HEAVY_TRAFFIC_CONGESTION));

  if (heavyTraffic) {
    const said = technician.heavy_traffic_travel;
    if (said === true || said === false) {
      parts.push(fromAnswer(said ? 1 : 0));
      notes.push(
        said ? "Said they still go in heavy traffic" : "Said they avoid heavy traffic",
      );
    } else {
      const congestion = traffic.roadClosure ? 1 : (traffic.congestion ?? 0);
      parts.push(clamp01(1 - congestion * exposure * share));
      notes.push("Heavy traffic (no answer on traffic yet)");
    }
  }

  if (parts.length === 0) {
    return { value: null, note: "Weather data unavailable" };
  }

  return { value: Math.min(...parts), note: notes.join("; ") };
}

/** Runs Stage 2 for one technician. */
export function scoreAcceptance(
  job: JobRow,
  technician: TechnicianRow,
  context: JobContext,
  distanceKm: number | null,
): {
  stage: StageResult;
  pricePhp: number | null;
  workload: number;
  etaMinutes: number | null;
} {
  const etaMinutes = travelMinutes(distanceKm, context.traffic.currentSpeed);

  const travel = travelBurdenScore(
    etaMinutes,
    context.travelExposure,
    context.traffic.available,
  );
  const workload = workloadScore(technician);
  const price = priceFitScore(job, technician);
  const coverage = coverageFitScore(distanceKm, technician.service_radius_km);
  const readiness = conditionsReadinessScore(technician, context, etaMinutes);

  const inputs: FactorInput[] = [
    {
      key: "travel_burden",
      label: "Travel burden",
      value: travel.value,
      weight: ACCEPTANCE_WEIGHTS.travel_burden,
      note: travel.note,
    },
    {
      key: "workload",
      label: "Current workload",
      value: workload.value,
      weight: ACCEPTANCE_WEIGHTS.workload,
      note: workload.note,
    },
    {
      key: "price_fit",
      label: "Price fit",
      value: price.value,
      weight: ACCEPTANCE_WEIGHTS.price_fit,
      note: price.note,
    },
    {
      key: "coverage_fit",
      label: "Coverage fit",
      value: coverage.value,
      weight: ACCEPTANCE_WEIGHTS.coverage_fit,
      note: coverage.note,
    },
    {
      key: "conditions_readiness",
      label: "Weather & traffic readiness",
      value: readiness.value,
      weight: ACCEPTANCE_WEIGHTS.conditions_readiness,
      note: readiness.note,
    },
  ];

  return {
    stage: combine(inputs),
    pricePhp: price.pricePhp,
    workload: workload.workload,
    etaMinutes,
  };
}
