/**
 * The server's fixed prices, checked against the app's.
 *
 * Reads `LaborPriceCatalog` straight out of the Dart source and compares
 * every symptom code and price with `LABOR_PRICE`. If the two ever disagree,
 * Price fit would be scoring a price the client was never shown.
 *
 * Run with Node's TypeScript stripping (no Deno needed):
 *
 *   cd supabase/functions/_shared
 *   node --experimental-strip-types labor_price.test.ts
 */
import { readFileSync } from "node:fs";
import {
  fixedJobPrice,
  LABOR_PRICE,
  laborAmount,
  urgentFee,
} from "./labor_price.ts";

let failures = 0;
function check(name: string, actual: unknown, expected: unknown) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(52)} ${actual}${ok ? "" : ` (expected ${expected})`}`);
}

// --------------------------------------------------- same list as the app
const dart = readFileSync(
  new URL(
    "../../../lib/features/rb_cars/models/labor_price_catalog.dart",
    import.meta.url,
  ),
  "utf8",
);

// Only the `fees` map inside `forJob` has the `'code': '₱...'` shape.
const appPrices = new Map<string, string>();
for (const m of dart.matchAll(/'([a-z0-9_]+)':\s*'(₱[^']*)'/g)) {
  appPrices.set(m[1], m[2]);
}

check("the app's price list was found", appPrices.size > 30, true);
check("same number of priced symptoms",
  Object.keys(LABOR_PRICE).length, appPrices.size);

for (const [code, fee] of appPrices) {
  check(`${code} matches the app`, LABOR_PRICE[code], fee);
}

// ------------------------------------------------------------ amounts
check("flat fee parses to pesos", laborAmount("laptop_blue_screen"), 600);
check("grouped thousands parse", laborAmount("appliance_aircon_install_split"), 3500);
check("per-camera fee has no single amount", laborAmount("cctv_new_install"), null);
check("unknown symptom has no price", laborAmount("not_sure"), null);
check("no symptom has no price", laborAmount(null), null);

// ------------------------------------- urgent fee, the app's own example
check("urgent fee: 20% of 600 is 120", urgentFee(600), 120);
check("urgent fee rounds to the peso (350 -> 70)", urgentFee(350), 70);
check("can wait: labor only", fixedJobPrice("laptop_blue_screen", "can_wait"), 600);
check("needed today: labor + 20%", fixedJobPrice("laptop_blue_screen", "need_today"), 720);
check("no flat price stays null when urgent", fixedJobPrice("cctv_new_install", "need_today"), null);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
