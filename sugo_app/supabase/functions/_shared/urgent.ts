/**
 * Urgent requests (2026-11-17): the user's rules, in one place.
 *
 * * An Urgent job's chosen technician has **five minutes** to accept. If they
 *   do not, `urgent-offer-sweep` passes the request to the next technician
 *   automatically - for urgent jobs only; a flexible job still goes back to
 *   the client to choose (the 2026-09-16 `shortlisted` rule).
 * * The request is sent as a "hard" notification (`PushMessage.urgent`).
 *
 * The app shows the same countdown from `job_matches.offered_at`
 * (`MatchResult.urgentWindow` must stay equal to [URGENT_RESPONSE_SECONDS]).
 */

export const URGENT_RESPONSE_SECONDS = 300;

/** True when the job was posted as Urgent. */
export function isUrgentJob(job: { urgency?: string | null }): boolean {
  return job.urgency === "need_today";
}

/** When an urgent request offered at [offeredAt] runs out, as ISO text. */
export function urgentDeadline(offeredAt: Date): string {
  return new Date(offeredAt.getTime() + URGENT_RESPONSE_SECONDS * 1000)
    .toISOString();
}

/** The push a technician gets for an urgent request. */
export function urgentOfferPush(
  clientFirstName: string,
  device: string,
  jobId: string,
  matchId: string,
  offeredAt: Date,
  passedOn = false,
): { title: string; body: string; urgent: true; data: Record<string, string> } {
  return {
    title: passedOn ? "URGENT request passed to you" : "URGENT job request",
    body: `${clientFirstName} needs a ${device} repair today. ` +
      "Accept within 5 minutes or it goes to another technician.",
    urgent: true,
    data: {
      type: "urgent_offer",
      job_id: jobId,
      match_id: matchId,
      expires_at: urgentDeadline(offeredAt),
    },
  };
}
