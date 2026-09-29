/**
 * TomTom Traffic Flow client.
 *
 * The key comes from `Deno.env.get("TOMTOM_API_KEY")`, set with
 * `npx supabase secrets set`. It never reaches the Flutter app: the phone asks
 * the edge function for scores, and the edge function asks TomTom.
 *
 * Sampled **once per job**, at the client's coordinate, not once per candidate
 * technician. One request instead of N, it stays inside the 2,500/day free
 * tier, and congestion around the destination is what actually decides arrival
 * time anyway.
 *
 * Every failure path returns `available: false`. Stage 2 then redistributes the
 * traffic weight rather than scoring every technician as stuck in traffic.
 */
import { EXTERNAL_API_TIMEOUT_MS, TRAFFIC_ZOOM } from "../scoring/constants.ts";
import type { TrafficContext } from "../scoring/types.ts";

const UNAVAILABLE: TrafficContext = {
  available: false,
  currentSpeed: null,
  freeFlowSpeed: null,
  congestion: null,
  roadClosure: false,
  label: null,
};

interface FlowSegmentResponse {
  flowSegmentData?: {
    currentSpeed?: number;
    freeFlowSpeed?: number;
    currentTravelTime?: number;
    freeFlowTravelTime?: number;
    confidence?: number;
    roadClosure?: boolean;
  };
}

/** Turns a 0..1 congestion ratio into the phrase shown on the match card. */
function describe(congestion: number, closed: boolean): string {
  if (closed) return "road closure nearby";
  if (congestion < 0.15) return "clear roads";
  if (congestion < 0.35) return "light traffic";
  if (congestion < 0.6) return "moderate traffic";
  return "heavy traffic";
}

export async function fetchTraffic(
  latitude: number | null,
  longitude: number | null,
): Promise<TrafficContext> {
  const key = Deno.env.get("TOMTOM_API_KEY");

  if (!key) {
    console.warn("TOMTOM_API_KEY is not set; traffic factor will be skipped");
    return UNAVAILABLE;
  }
  if (latitude === null || longitude === null) {
    return UNAVAILABLE;
  }

  const url =
    `https://api.tomtom.com/traffic/services/4/flowSegmentData/absolute/` +
    `${TRAFFIC_ZOOM}/json?point=${latitude},${longitude}&unit=KMPH&key=${key}`;

  try {
    const response = await fetch(url, {
      signal: AbortSignal.timeout(EXTERNAL_API_TIMEOUT_MS),
    });

    if (!response.ok) {
      console.warn(`TomTom returned ${response.status}`);
      return UNAVAILABLE;
    }

    const body = (await response.json()) as FlowSegmentResponse;
    const segment = body.flowSegmentData;

    if (!segment || typeof segment.currentSpeed !== "number") {
      return UNAVAILABLE;
    }

    const current = segment.currentSpeed;
    const freeFlow = segment.freeFlowSpeed ?? current;
    const roadClosure = segment.roadClosure === true;

    // Congestion: how far below free-flow speed the road is running.
    const congestion = freeFlow > 0
      ? Math.max(0, Math.min(1, 1 - current / freeFlow))
      : 0;

    return {
      available: true,
      currentSpeed: current,
      freeFlowSpeed: freeFlow,
      congestion: Math.round(congestion * 1000) / 1000,
      roadClosure,
      label: describe(congestion, roadClosure),
    };
  } catch (error) {
    // Timeout, DNS failure, malformed JSON - all the same to the caller.
    console.warn("TomTom request failed", (error as Error).message);
    return UNAVAILABLE;
  }
}
