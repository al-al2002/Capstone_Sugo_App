/**
 * `rerouted_mid_job`, worked out from the match snapshot (2026-11-16).
 *
 * Run with Node's TypeScript stripping (no Deno needed):
 *
 *   cd supabase/functions/_shared
 *   node --experimental-strip-types reroute.test.ts
 */
import { snapshotServicePath, wasRerouted } from "./reroute.ts";

let failures = 0;
function check(name: string, actual: unknown, expected: unknown) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(52)} ${actual}${ok ? "" : ` (expected ${expected})`}`);
}

check("home visit, still a home visit: not rerouted", wasRerouted("home_service", "home_service"), false);
check("home visit, now a pickup: rerouted", wasRerouted("home_service", "pickup"), true);
check("booked as a pickup: not rerouted", wasRerouted("pickup", "pickup"), false);
check("no snapshot: unknown", wasRerouted(undefined, "pickup"), null);
check("empty snapshot path: unknown", wasRerouted("", "pickup"), null);
check("no current path: unknown", wasRerouted("home_service", null), null);

check("reads score_breakdown.job.service_path",
  snapshotServicePath({ job: { service_path: "home_service" } }), "home_service");
check("no job in the breakdown", snapshotServicePath({ version: 2 }), undefined);
check("no breakdown at all", snapshotServicePath(null), undefined);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
if (failures > 0) process.exit(1);
