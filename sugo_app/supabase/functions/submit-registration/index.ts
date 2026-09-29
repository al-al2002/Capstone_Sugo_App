/**
 * Files a finished registration for admin review. Both roles.
 *
 * ```
 * POST /functions/v1/submit-registration
 * (no body — the caller is identified by their JWT)
 *
 * -> { registration_status: "pending_review", changed: true }
 * ```
 *
 * ## Why this cannot be a direct table update
 *
 * `profiles.registration_status` is guarded twice over, and both guards exist
 * for the same reason: an account must not be able to approve itself.
 *
 * **1. The trigger.** `guard_registration_status()` from 20260907000001 lets a
 * user move themselves from `incomplete` to `pending_review` and nothing else.
 * Reaching `active` requires a null `auth.uid()`, which only the service role
 * has.
 *
 * **2. The completeness checks.** Even the one permitted transition has
 * conditions - a submitted ID, a verified phone, a passed assessment. Those
 * live in `submit_registration_for_review()`, which is service-role only. If
 * the app could write `pending_review` itself it would simply skip them, and a
 * reviewer would receive half-finished applications.
 *
 * So the app asks; the server checks and decides.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, serviceClient } from "../_shared/supabase.ts";

interface ProfileRow {
  role: string;
  registration_status: string;
}

/**
 * Postgres error codes raised deliberately by the SQL function.
 *
 * `23514` (check_violation) means a requirement is missing - the message is
 * written for the applicant and is safe to show. Anything else is an internal
 * fault and gets a generic message, because an unfiltered Postgres error can
 * leak column and policy names.
 */
const REQUIREMENT_NOT_MET = "23514";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const db = serviceClient();

    const { data: profile, error: profileError } = await db
      .from("profiles")
      .select("role, registration_status")
      .eq("id", uid)
      .maybeSingle<ProfileRow>();

    if (profileError) {
      return fail("Could not load your profile", 500, profileError.message);
    }
    if (!profile) {
      return fail("No profile found for this account", 409);
    }

    // A client's trust profile is created here rather than by the app, so its
    // starting values cannot be chosen by the account they describe - a client
    // who could insert their own row would open at `trusted`.
    if (profile.role === "client") {
      const { error: trustError } = await db.rpc(
        "initialize_client_trust_profile",
        { p_client_id: uid },
      );

      if (trustError) {
        return fail(
          "Could not set up your client profile",
          500,
          trustError.message,
        );
      }
    }

    const { data, error } = await db.rpc("submit_registration_for_review", {
      p_user_id: uid,
    });

    if (error) {
      if (error.code === REQUIREMENT_NOT_MET) {
        // Raised by the SQL function with a message written for the applicant,
        // e.g. "Phone verification is required".
        return fail(error.message, 409);
      }
      return fail("Could not submit your registration", 500, error.message);
    }

    console.log(
      `submit-registration: ${profile.role} ${uid} -> pending_review`,
    );

    return json(data ?? { registration_status: "pending_review" });
  } catch (error) {
    return fail(
      "Could not submit your registration",
      500,
      (error as Error).message,
    );
  }
});
