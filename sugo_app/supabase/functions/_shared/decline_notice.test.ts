/**
 * The decline push: the tray wording, and the data the app's pop-up reads.
 *
 * Run with Node's TypeScript stripping (no Deno needed):
 *
 *   cd supabase/functions/_shared
 *   node --experimental-strip-types decline_notice.test.ts
 */
import { declineNotice } from "./decline_notice.ts";

let failures = 0;
function check(name: string, actual: unknown, expected: unknown) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(48)} ${actual}${ok ? "" : ` (expected ${expected})`}`);
}

const base = { jobId: "job-1", technician: "Ryan", noun: "laptop" };

// Shortlist left: the choice goes back to the client.
const shortlist = declineNotice({ ...base, next: "shortlist" });
check("title names the technician", shortlist.title, "Ryan can't take this one");
check(
  "shortlist body",
  shortlist.body,
  "Choose another technician for your laptop - your shortlist is still there.",
);
check("data type", shortlist.data?.type, "declined");
check("data job_id", shortlist.data?.job_id, "job-1");
check("data name (for the pop-up)", shortlist.data?.name, "Ryan");
check("data next = shortlist", shortlist.data?.next, "shortlist");

// Shortlist ran out, a fresh match found more.
const more = declineNotice({ ...base, next: "more" });
check(
  "more body",
  more.body,
  "We found more technicians for your laptop. Open SUGO to choose one.",
);
check("data next = more", more.data?.next, "more");

// Nobody else.
const none = declineNotice({ ...base, noun: "phone", next: "none" });
check(
  "none body",
  none.body,
  "No other technician is free for your phone right now. Open SUGO to try again.",
);
check("data next = none", none.data?.next, "none");

// The fallback name reads as a sentence too.
check(
  "fallback name",
  declineNotice({ ...base, technician: "Your technician", next: "more" }).title,
  "Your technician can't take this one",
);

// FCM data values must all be strings.
check(
  "every data value is a string",
  Object.values(shortlist.data ?? {}).every((v) => typeof v === "string"),
  true,
);

console.log(failures === 0 ? "\nAll passed." : `\n${failures} failed.`);
if (failures > 0) process.exit(1);
