/**
 * The work record's checkpoint names and the "add photos first" message.
 *
 *   cd supabase/functions/_shared
 *   node --experimental-strip-types evidence.test.ts
 */
import { milestoneLabel, missingEvidenceMessage } from "./evidence.ts";

let failures = 0;
function check(name: string, actual: unknown, expected: unknown) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(52)} ${ok ? "" : `${actual} (expected ${expected})`}`);
}

check("home visit: intake is Before", milestoneLabel("intake", "home_service", null), "Before");
check("pickup: intake is Collected", milestoneLabel("intake", "pickup", "delivery"), "Collected");
check("pickup, not chosen yet: Collected", milestoneLabel("intake", "pickup", null), "Collected");
check("drop-off: intake is Unit received", milestoneLabel("intake", "pickup", "self"), "Unit received");
check("home visit: after is After", milestoneLabel("after", "home_service", null), "After");
check("shop: after is After repair", milestoneLabel("after", "pickup", "self"), "After repair");

check("both missing, home visit",
  missingEvidenceMessage(["intake", "after"], "home_service", null),
  "Add the Before and After photos to the work record before marking this job complete.");
check("only After missing, drop-off",
  missingEvidenceMessage(["after"], "pickup", "self"),
  "Add the After repair photo to the work record before marking this job complete.");

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
