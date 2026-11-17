/**
 * Shop pickup/delivery fee (2026-11-16).
 *
 *   billed km = distance rounded UP to the next whole km
 *   one trip, up to 3 km: PHP 50
 *   one trip, beyond:     PHP 50 + PHP 15 for each km after the third
 *   pickup and delivery:  2 trips (2026-11-17)
 *
 * Pickup and delivery is two drives for the technician - collecting the unit
 * and bringing it back - so since 2026-11-17 it is charged as two trips, at
 * the user's request. `tripFee` is one trip; `deliveryFee`, the fee saved on
 * a job, is the two.
 *
 * The SERVER's copy of the rule. The fee saved on a job is calculated here,
 * from the technician's shop location, so a client cannot send their own.
 * The app shows the same breakdown with `DeliveryFee.calculate()` in
 * `lib/features/rb_cars/models/delivery_fee.dart`. Change the rates in BOTH
 * places - `delivery_fee.test.ts` and `delivery_fee_test.dart` pin the same
 * cases, so a mismatch fails a test.
 */
import { distanceBetween } from "../match-technician/scoring/geo.ts";

/** Everything up to this many km costs the base fee. */
export const DELIVERY_BASE_KM = 3;
export const DELIVERY_BASE_FEE = 50;
export const DELIVERY_PER_KM_FEE = 15;
/** Pickup and delivery: collecting the unit, and bringing it back. */
export const PICKUP_DELIVERY_TRIPS = 2;

/** Whole km billed: 3.2 km is 4 km. Never negative. */
export function billedKm(distanceKm: number): number {
  return Math.max(0, Math.ceil(distanceKm));
}

/** One trip, in whole pesos. */
export function tripFee(distanceKm: number): number {
  const km = billedKm(distanceKm);
  if (km <= DELIVERY_BASE_KM) return DELIVERY_BASE_FEE;
  return DELIVERY_BASE_FEE + DELIVERY_PER_KM_FEE * (km - DELIVERY_BASE_KM);
}

/**
 * The pickup-and-delivery fee saved on a job, in whole pesos: two trips.
 * Self drop-off is 0 and never calls this.
 */
export function deliveryFee(distanceKm: number): number {
  return PICKUP_DELIVERY_TRIPS * tripFee(distanceKm);
}

/** A technician's location columns, as far as the shop goes. */
export interface ShopLocation {
  shop_latitude: number | null;
  shop_longitude: number | null;
  base_latitude: number | null;
  base_longitude: number | null;
}

/**
 * Straight-line km from the job pin to the technician's shop, 2 dp.
 *
 * `shop_*` first, then `base_*` - the same fallback the client's collection
 * route uses (20260916000008), and never the live position, which on a
 * working day is somebody else's house. Null when either end is unknown.
 */
export function shopDistanceKm(
  jobLat: number | null,
  jobLng: number | null,
  technician: ShopLocation,
): number | null {
  const lat = technician.shop_latitude ?? technician.base_latitude;
  const lng = technician.shop_longitude ?? technician.base_longitude;
  const km = distanceBetween(jobLat, jobLng, lat, lng);
  return km === null ? null : Math.round(km * 100) / 100;
}
