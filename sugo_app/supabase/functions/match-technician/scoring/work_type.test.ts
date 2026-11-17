/**
 * The work-type gate, pinned (2026-11-17).
 *
 * Run with Node's TypeScript stripping (no Deno needed):
 *
 *   cd supabase/functions/match-technician/scoring
 *   node --experimental-strip-types work_type.test.ts
 */
import { takesWorkFor, workTypeLabel } from "./work_type.ts";

let failures = 0;
function check(name: string, actual: unknown, expected: unknown) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(58)} ${actual}${ok ? "" : ` (expected ${expected})`}`);
}

const homeOnly = { offers_home_service: true, offers_shop_repair: false };
const shopOnly = { offers_home_service: false, offers_shop_repair: true };
const both = { offers_home_service: true, offers_shop_repair: true };
const beforeMigration = {};

check("Home Service: a home-service technician", takesWorkFor(homeOnly, "home_service"), true);
check("Home Service: never a shop-only one", takesWorkFor(shopOnly, "home_service"), false);
check("Home Service: one who does both", takesWorkFor(both, "home_service"), true);

check("Shop Repair: a shop technician", takesWorkFor(shopOnly, "pickup"), true);
check("Shop Repair: never a home-only one", takesWorkFor(homeOnly, "pickup"), false);
check("Shop Repair: one who does both", takesWorkFor(both, "pickup"), true);

check("no flags (an older view) still matches", takesWorkFor(beforeMigration, "pickup"), true);
check("null flags still match", takesWorkFor({ offers_shop_repair: null }, "pickup"), true);
check("a community question is not gated", takesWorkFor(homeOnly, "it_community"), true);
check("a job with no path is not gated", takesWorkFor(shopOnly, null), true);

check("the label for a shop job", workTypeLabel("pickup"), "Shop Repair");
check("the label for a home job", workTypeLabel("home_service"), "Home Service");

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
if (failures > 0) process.exit(1);
