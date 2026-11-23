/**
 * What the client is told when the technician they chose declines.
 * (2026-11-17; the `name` / `next` data added 2026-11-23.)
 *
 * The title and body are what Android shows in the tray when SUGO is closed.
 * When SUGO is OPEN, Android shows nothing, so the app raises its own pop-up
 * from the `data` instead (`DeclinedAlertDialog`):
 *
 *   type  "declined"
 *   job_id
 *   name  the technician's first name (or "Your technician")
 *   next  what the client can do now:
 *           "shortlist" - others from the same match are still there
 *           "more"      - the shortlist ran out; a fresh match found more
 *           "none"      - nobody else is free right now
 *
 * Pure, so it is tested without a database (decline_notice.test.ts).
 */
import type { PushMessage } from "./fcm.ts";

export type DeclineNext = "shortlist" | "more" | "none";

export function declineNotice(input: {
  jobId: string;
  technician: string;
  noun: string;
  next: DeclineNext;
}): PushMessage {
  const { jobId, technician, noun, next } = input;

  const body = next === "shortlist"
    ? `Choose another technician for your ${noun} - your shortlist is ` +
      "still there."
    : next === "more"
    ? `We found more technicians for your ${noun}. Open SUGO to choose one.`
    : `No other technician is free for your ${noun} right now. Open SUGO ` +
      "to try again.";

  return {
    title: `${technician} can't take this one`,
    body,
    data: { type: "declined", job_id: jobId, name: technician, next },
  };
}
