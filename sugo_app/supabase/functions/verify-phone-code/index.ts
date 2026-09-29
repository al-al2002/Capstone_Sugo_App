/**
 * Checks a one-time code and marks the phone verified.
 *
 * ```
 * POST /functions/v1/verify-phone-code
 * { "code": "482913" }
 *
 * -> { verified: true, phone }
 *  | { verified: false, reason, attempts_left? }
 * ```
 *
 * ## Why the comparison happens here
 *
 * RLS on `phone_verifications` has no permissive policy for `authenticated`,
 * which denies everything by default, and `select (code)` is revoked on top of
 * that. The app therefore cannot read the code it is being asked to match -
 * which is the entire point. A client that can see the answer is not
 * verifying anything.
 *
 * Attempt counting, expiry and the five-guess ceiling all live in
 * `verify_phone_code()` so they apply no matter what calls it.
 *
 * ## A failed code is not an HTTP error
 *
 * A wrong code returns 200 with `verified: false`. It is an expected outcome of
 * a user typing, not a fault - and the distinction matters to the client, which
 * shows a field-level correction for one and a flow-level error banner for the
 * other.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, readJson, serviceClient } from "../_shared/supabase.ts";

interface VerifyRequest {
  code?: string;
}

interface VerifyResult {
  verified: boolean;
  reason?: string;
  phone?: string;
  attempts_left?: number;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const body = await readJson<VerifyRequest>(req);
    const code = (body.code ?? "").trim();

    if (!/^\d{6}$/.test(code)) {
      // Shaped like a verification failure rather than a validation error, so
      // the client renders it under the code field like any wrong code.
      return json({ verified: false, reason: "incorrect" } satisfies VerifyResult);
    }

    const db = serviceClient();

    const { data, error } = await db.rpc("verify_phone_code", {
      p_user_id: uid,
      p_code: code,
    });

    if (error) {
      return fail("Could not check that code", 500, error.message);
    }

    const result = (data ?? { verified: false }) as VerifyResult;

    // The code itself is never logged - it is a live credential until it is
    // consumed, and function logs are retained and readable by anyone with
    // project access.
    console.log(
      `verify-phone-code: ${uid} -> ${result.verified ? "verified" : result.reason}`,
    );

    return json(result);
  } catch (error) {
    return fail("Could not check that code", 500, (error as Error).message);
  }
});
