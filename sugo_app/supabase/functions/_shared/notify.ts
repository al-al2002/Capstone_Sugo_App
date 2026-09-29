/**
 * Sending a push to a person, rather than to a device.
 *
 * FCM addresses installs; everything in SUGO thinks in people. This is the
 * one place that turns "tell the client" into "every device the client is
 * signed in on", and that tidies away installs FCM says are gone. The delay
 * push in `eta_sampler.ts` predates it and does the same thing inline.
 *
 * Never throws. A notification is a courtesy on top of something that has
 * already happened - a message saved, a stage moved, a booking made - and a
 * failure to announce it must never undo or block the thing itself.
 */
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

import { type PushMessage, sendPush } from "./fcm.ts";

/** Sends [message] to every device of [userId]. Returns how many got it. */
export async function notifyUser(
  db: SupabaseClient,
  userId: string | null | undefined,
  message: PushMessage,
): Promise<number> {
  if (!userId) return 0;

  try {
    const { data: devices } = await db
      .from("device_tokens")
      .select("token")
      .eq("user_id", userId)
      .returns<{ token: string }[]>();

    const tokens = (devices ?? []).map((row) => row.token);
    if (tokens.length === 0) return 0;

    const result = await sendPush(tokens, message);

    // FCM said these installs are gone; deleting on the reply is what keeps
    // device_tokens self-cleaning.
    if (result.stale.length > 0) {
      await db.from("device_tokens").delete().in("token", result.stale);
    }
    return result.sent;
  } catch (error) {
    console.warn("notifyUser failed", (error as Error).message);
    return 0;
  }
}

/** A person's first name for a notification title, or a neutral fallback. */
export async function firstNameOf(
  db: SupabaseClient,
  userId: string | null | undefined,
  fallback: string,
): Promise<string> {
  if (!userId) return fallback;
  try {
    const { data } = await db
      .from("profiles")
      .select("full_name")
      .eq("id", userId)
      .maybeSingle<{ full_name: string | null }>();
    const first = data?.full_name?.trim().split(/\s+/)[0];
    return first && first.length > 0 ? first : fallback;
  } catch {
    return fallback;
  }
}

/**
 * How a notification refers to the unit: "your laptop", "your appliance".
 * `network` covers routers and CCTV, so it is simply "device".
 */
export function deviceNoun(deviceType: string | null | undefined): string {
  switch (deviceType) {
    case "laptop":
      return "laptop";
    case "phone":
      return "phone";
    case "appliance":
      return "appliance";
    default:
      return "device";
  }
}

/** Trims a message preview to what a notification shade shows anyway. */
export function preview(text: string, max = 140): string {
  const flat = text.replace(/\s+/g, " ").trim();
  return flat.length <= max ? flat : `${flat.slice(0, max - 1).trimEnd()}…`;
}
