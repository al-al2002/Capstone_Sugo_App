/**
 * When to say "almost there" (2026-11-17).
 *
 * Once per trip, as the estimate crosses into the last few minutes, and only
 * on a leg that ends where someone is waiting. Stateless on purpose - no
 * column records that it was said: the previous sample's estimate is still
 * on the tracking row, so "it was further than this then, and within it now"
 * is the crossing, and it happens once. Kept free of Supabase so it can be
 * tested with Node alone (`arrival.test.ts`).
 */

/** Three minutes: long enough to get to the door, short enough to mean it. */
export const ARRIVING_SOON_MINUTES = 3;

export function announcesArrival(leg: {
  /** Minutes away at the previous sample, or null on the first one. */
  previousEtaMinutes: number | null;
  /** Minutes away now. */
  etaMinutes: number;
  /** The client heading to the shop, or the technician heading to the client. */
  endsWithSomeoneWaiting: boolean;
}): boolean {
  return leg.endsWithSomeoneWaiting &&
    leg.previousEtaMinutes !== null &&
    leg.previousEtaMinutes > ARRIVING_SOON_MINUTES &&
    leg.etaMinutes <= ARRIVING_SOON_MINUTES;
}
