/**
 * Distance helpers.
 *
 * Straight-line (great-circle) distance, not road distance. A routing API call
 * per technician would be N requests per match and would blow the free tier on
 * a single demo; TomTom is instead sampled once at the job site for congestion.
 * Over the ~25 km service radius that matters here, straight-line distance
 * ranks candidates in the same order road distance would, which is all a
 * ranking function needs.
 */

const EARTH_RADIUS_KM = 6371;

const toRadians = (degrees: number): number => (degrees * Math.PI) / 180;

/** Great-circle distance in kilometres. */
export function haversineKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
): number {
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);

  return EARTH_RADIUS_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/** Null-safe wrapper: any missing coordinate yields null, not a wrong number. */
export function distanceBetween(
  aLat: number | null | undefined,
  aLon: number | null | undefined,
  bLat: number | null | undefined,
  bLon: number | null | undefined,
): number | null {
  if (
    aLat === null || aLat === undefined ||
    aLon === null || aLon === undefined ||
    bLat === null || bLat === undefined ||
    bLon === null || bLon === undefined
  ) {
    return null;
  }
  return haversineKm(aLat, aLon, bLat, bLon);
}

/**
 * Rough travel time in minutes, given a distance and the live average speed
 * TomTom reported. Falls back to a 20 km/h city average when traffic data is
 * unavailable. Used only for the "~18 min travel" explainability line, never
 * as a scoring input, so an imprecise fallback is harmless.
 */
export function travelMinutes(
  distanceKm: number | null,
  currentSpeedKmh: number | null,
): number | null {
  if (distanceKm === null) return null;
  const speed = currentSpeedKmh && currentSpeedKmh > 5 ? currentSpeedKmh : 20;
  return (distanceKm / speed) * 60;
}

/** Clamps any number into 0..1, so a factor can never break a stage score. */
export function clamp01(value: number): number {
  if (Number.isNaN(value)) return 0;
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}
