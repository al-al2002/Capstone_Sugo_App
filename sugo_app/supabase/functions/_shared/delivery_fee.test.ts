/**
 * The server's delivery fee, on the same cases as the app's
 * `delivery_fee_test.dart`. If the two ever disagree, the fee a client was
 * shown is not the fee saved on their job - so both are pinned.
 *
 * Run with Node's TypeScript stripping (no Deno needed):
 *
 *   cd supabase/functions/_shared
 *   node --experimental-strip-types delivery_fee.test.ts
 */
import { billedKm, deliveryFee, shopDistanceKm, tripFee } from "./delivery_fee.ts";

let failures = 0;
function check(name: string, actual: unknown, expected: unknown) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(48)} ${actual}${ok ? "" : ` (expected ${expected})`}`);
}

// One trip: the brief's five cases.
check("trip 1 km -> 50", tripFee(1), 50);
check("trip 3 km -> 50", tripFee(3), 50);
check("trip 4 km -> 65", tripFee(4), 65);
check("trip 5 km -> 80", tripFee(5), 80);
check("trip 8 km -> 125", tripFee(8), 125);

// Pickup and delivery: two trips (2026-11-17).
check("pickup+delivery 1 km -> 100", deliveryFee(1), 100);
check("pickup+delivery 3 km -> 100", deliveryFee(3), 100);
check("pickup+delivery 4 km -> 130", deliveryFee(4), 130);
check("pickup+delivery 5 km -> 160", deliveryFee(5), 160);
check("pickup+delivery 8 km -> 250", deliveryFee(8), 250);

// Rounding up to the next whole km.
check("0.4 km bills as 1 km", billedKm(0.4), 1);
check("3.0 km stays 3 km -> 100", deliveryFee(3.0), 100);
check("3.01 km bills as 4 km -> 130", deliveryFee(3.01), 130);
check("7.2 km bills as 8 km -> 250", deliveryFee(7.2), 250);

// Shop first, base as the fallback, null when unknown.
const job = { lat: 7.0731, lng: 125.6128 };
const atBase = shopDistanceKm(job.lat, job.lng, {
  shop_latitude: null, shop_longitude: null, base_latitude: 7.0731, base_longitude: 125.6128,
});
check("no shop set: measured to base", atBase, 0);
const shopFar = shopDistanceKm(job.lat, job.lng, {
  shop_latitude: 7.1, shop_longitude: 125.6128, base_latitude: 7.0731, base_longitude: 125.6128,
});
check("shop set: measured to the shop (~2.99 km)", shopFar, 2.99);
check("no location at all: null", shopDistanceKm(job.lat, job.lng, {
  shop_latitude: null, shop_longitude: null, base_latitude: null, base_longitude: null,
}), null);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
