/**
 * Book-and-cancel cooldown (2026-11-17), the server half.
 *
 * The rule itself - 2+ cancels in a rolling hour pause booking for 2 minutes
 * after the latest one - lives in ONE place, the SQL function
 * `booking_cooldown_until` (migration 20261117000004). This file only records
 * cancels and asks that function, so the numbers cannot drift between the
 * database and here.
 *
 * ## Why a failed check lets the booking through ("fail open")
 *
 * The pause is an anti-abuse measure, not a safety gate. If the check itself
 * breaks - the migration not applied yet, a network blip - refusing every
 * booking for every client would be far worse than letting one troll book
 * once more. So an error is logged and treated as "not paused".
 */
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

/** When this client may book again (ISO time), or null if they may now. */
export async function bookingPausedUntil(
  db: SupabaseClient,
  clientId: string,
): Promise<string | null> {
  const { data, error } = await db.rpc("booking_cooldown_until", {
    p_client_id: clientId,
  });
  if (error) {
    console.error("booking cooldown check failed; not pausing", error.message);
    return null;
  }
  return (data as string | null) ?? null;
}

/**
 * Logs that [clientId] cancelled a booking with [technicianId] on [jobId],
 * and returns when they may book again (null if not paused).
 *
 * Never throws: the cancel it records has already happened, and failing the
 * request now would tell the client it did not.
 */
export async function recordBookingCancellation(
  db: SupabaseClient,
  clientId: string,
  jobId: string,
  technicianId: string,
  kind: "withdraw" | "delete",
): Promise<string | null> {
  const { error } = await db.from("booking_cancellations").insert({
    client_id: clientId,
    job_id: jobId,
    technician_id: technicianId,
    kind,
  });
  if (error) {
    console.error("could not record a booking cancellation", error.message);
    return null;
  }
  return await bookingPausedUntil(db, clientId);
}
