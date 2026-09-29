/**
 * Deletes the caller's own account, but only while registration is unfinished.
 *
 * ```
 * POST /functions/v1/cancel-registration
 * -> { deleted: true, user_id }
 * ```
 *
 * ## Why this exists
 *
 * Supabase Auth creates the `auth.users` row the moment someone signs up, long
 * before they pick a role or submit an ID. Backing out of onboarding used to
 * leave an account that could log in, held their email address hostage, and
 * counted as a user while being able to do nothing at all.
 *
 * This gives that person an exit: "Cancel registration" removes the account
 * outright. `profiles` cascades from `auth.users`, `technicians` cascades from
 * `profiles`, and the assessment and portfolio tables cascade from
 * `technicians`, so one delete clears everything.
 *
 * ## Two guards, and why the second is structural
 *
 * **1. Registration must be unfinished.** If `onboarding_completed_at` is set,
 * this refuses. A finished account is a real account, and deleting one is a
 * different operation with different consequences (booking history, ratings
 * other people rely on) that should not share an endpoint with "I changed my
 * mind during signup".
 *
 * **2. The database refuses accounts with activity.** `jobs`, `job_matches`
 * and `job_outcomes` reference profiles and technicians *without*
 * `on delete cascade`. That is deliberate: if a delete would destroy real
 * marketplace history, Postgres raises a foreign-key violation and this
 * function reports it rather than proceeding. The safety net is a constraint,
 * not a condition someone could forget to write.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const db = serviceClient();

    const { data: profile, error: profileError } = await db
      .from("profiles")
      .select("id, onboarding_completed_at")
      .eq("id", uid)
      .maybeSingle<{ id: string; onboarding_completed_at: string | null }>();

    if (profileError) {
      return fail("Could not load your account", 500, profileError.message);
    }

    // No profile row at all: the auth user exists but the trigger never ran, or
    // it was already cleaned up. Deleting the auth user is still the right
    // outcome, so fall through rather than erroring.
    if (profile?.onboarding_completed_at) {
      return fail(
        "This account has finished registration. Use account deletion in "
          + "settings instead.",
        409,
      );
    }

    const { error: deleteError } = await db.auth.admin.deleteUser(uid);

    if (deleteError) {
      const message = deleteError.message.toLowerCase();

      // The FK guard firing. Something real is attached to this account, so
      // refuse loudly instead of trying to force it.
      if (
        message.includes("foreign key") ||
        message.includes("violates") ||
        message.includes("constraint")
      ) {
        return fail(
          "This account already has bookings attached and cannot be removed "
            + "automatically. Please contact support.",
          409,
          deleteError.message,
        );
      }

      return fail("Could not remove your account", 500, deleteError.message);
    }

    console.log(`cancel-registration: deleted incomplete account ${uid}`);

    return json({ deleted: true, user_id: uid });
  } catch (error) {
    return fail(
      "Could not cancel your registration",
      500,
      (error as Error).message,
    );
  }
});
