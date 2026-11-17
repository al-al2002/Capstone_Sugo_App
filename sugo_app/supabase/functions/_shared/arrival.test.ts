/**
 * "Almost there", pinned (2026-11-17).
 *
 *   cd supabase/functions/_shared
 *   node --experimental-strip-types arrival.test.ts
 */
import { announcesArrival } from "./arrival.ts";

let failures = 0;
function check(name: string, actual: unknown, expected: unknown) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(58)} ${actual}${ok ? "" : ` (expected ${expected})`}`);
}

const waiting = { endsWithSomeoneWaiting: true };

check("6 min then 2 min: say it", announcesArrival({ ...waiting, previousEtaMinutes: 6, etaMinutes: 2 }), true);
check("exactly 3 min counts as almost there", announcesArrival({ ...waiting, previousEtaMinutes: 5, etaMinutes: 3 }), true);
check("2 min then 1 min: already said", announcesArrival({ ...waiting, previousEtaMinutes: 2, etaMinutes: 1 }), false);
check("still 8 min away: not yet", announcesArrival({ ...waiting, previousEtaMinutes: 12, etaMinutes: 8 }), false);
check("first sample already close: no repeat of 'on the way'", announcesArrival({ ...waiting, previousEtaMinutes: null, etaMinutes: 2 }), false);
check("heading to the shop with the unit: nobody waiting", announcesArrival({ endsWithSomeoneWaiting: false, previousEtaMinutes: 6, etaMinutes: 2 }), false);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
if (failures > 0) process.exit(1);
