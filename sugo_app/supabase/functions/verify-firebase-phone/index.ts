/**
 * Records a phone number that Firebase verified, after checking the proof.
 *
 * ```
 * POST /functions/v1/verify-firebase-phone
 * { "id_token": "<Firebase ID token>" }
 *
 * -> { phone_verified: true, phone: "+639171234567" }
 * ```
 *
 * ## Why this function exists at all
 *
 * The app could simply tell Supabase "Firebase verified me". That would be
 * worthless: anyone can send that request. The whole point of a verification
 * step is that the server does not take the client's word for it.
 *
 * A Firebase ID token is proof, because it is a JWT **signed by Google** with
 * a private key nobody else has, and it carries the verified `phone_number` as
 * a claim. This function verifies that signature against Google's published
 * public keys before writing anything.
 *
 * ## What is checked, and why each one matters
 *
 * Skipping any of these makes the check decorative:
 *
 * 1. **Signature** against Google's current keys. Without it, a forged token
 *    with any phone number is accepted - the entire check reduces to trusting
 *    the caller again.
 * 2. **`alg` is RS256.** A token claiming `alg: none`, or HS256 with the
 *    public key as the secret, is the classic JWT bypass.
 * 3. **`aud` is our Firebase project.** Otherwise a token minted by ANY
 *    Firebase project - including one the attacker owns - would be accepted.
 * 4. **`iss` is Google's securetoken issuer for our project.**
 * 5. **`exp` in the future, `iat` not in the future.** Stops replay of an old
 *    captured token.
 * 6. **A `phone_number` claim exists.** An email or anonymous Firebase user
 *    has a perfectly valid token and no verified phone.
 *
 * The Supabase caller is identified separately, from their own JWT, so the
 * number is attached to the right SUGO account. The Firebase token says which
 * NUMBER is verified; the Supabase token says WHO is claiming it.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, readJson, serviceClient } from "../_shared/supabase.ts";

/**
 * Google's public keys for Firebase ID tokens, in JWK form.
 *
 * The JWK endpoint is used rather than the X.509 one because `crypto.subtle`
 * imports JWK directly; the X.509 variant would need the SPKI pulled out of a
 * PEM certificate by hand.
 */
const JWKS_URL =
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

/**
 * The Firebase project whose tokens we accept.
 *
 * Set as a secret so a different project can be pointed at without a redeploy:
 *   supabase secrets set FIREBASE_PROJECT_ID=sugo-e559c
 */
const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";

/**
 * Clock skew tolerance, in seconds.
 *
 * Two minutes. A phone with a slightly fast clock produces a token whose
 * `iat` is marginally in the future, and rejecting that would fail real users
 * for no security gain. Too generous a window would widen the replay surface,
 * so it stays small.
 */
const CLOCK_SKEW = 120;

interface VerifyRequest {
  id_token?: string;
}

interface JwkKey {
  kid: string;
  kty: string;
  alg: string;
  use?: string;
  n: string;
  e: string;
}

/** Cached keys, so every verification does not refetch them. */
let cachedKeys: { keys: JwkKey[]; fetchedAt: number } | null = null;

/**
 * Google rotates these keys. One hour is well inside the rotation period, and
 * an unknown `kid` forces a refetch anyway (see `keyFor`), so a rotation mid
 * cache-window is handled rather than failing until the cache expires.
 */
const KEY_CACHE_MS = 60 * 60 * 1000;

async function fetchKeys(force = false): Promise<JwkKey[]> {
  const fresh = cachedKeys &&
    Date.now() - cachedKeys.fetchedAt < KEY_CACHE_MS;

  if (fresh && !force) return cachedKeys!.keys;

  const response = await fetch(JWKS_URL);
  if (!response.ok) {
    throw new Error(`Could not fetch Google signing keys (${response.status})`);
  }

  const body = await response.json() as { keys?: JwkKey[] };
  const keys = body.keys ?? [];

  cachedKeys = { keys, fetchedAt: Date.now() };
  return keys;
}

/** Finds the key that signed this token, refetching once if it is unknown. */
async function keyFor(kid: string): Promise<JwkKey | null> {
  let keys = await fetchKeys();
  let match = keys.find((k) => k.kid === kid);

  if (!match) {
    // Likely a rotation since the cache was filled.
    keys = await fetchKeys(true);
    match = keys.find((k) => k.kid === kid);
  }

  return match ?? null;
}

/** base64url -> bytes. */
function decodeSegment(segment: string): Uint8Array {
  const padded = segment.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded + "=".repeat((4 - padded.length % 4) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function decodeJson(segment: string): Record<string, unknown> {
  return JSON.parse(new TextDecoder().decode(decodeSegment(segment)));
}

interface VerifiedToken {
  uid: string;
  phone: string | null;
}

/**
 * Verifies a Firebase ID token and returns its subject and phone claim.
 *
 * Throws with a specific reason on every failure. The caller turns those into
 * one generic message for the user - a verifier that explains precisely why a
 * forged token was rejected is a tool for forging a better one - while the
 * detail still reaches the function logs.
 */
async function verifyIdToken(token: string): Promise<VerifiedToken> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("Malformed token");

  const [headerSegment, payloadSegment, signatureSegment] = parts;

  const header = decodeJson(headerSegment) as { alg?: string; kid?: string };

  // Check 2: only RS256. `none` and HS256 confusion are the standard bypasses.
  if (header.alg !== "RS256") {
    throw new Error(`Unexpected algorithm: ${header.alg}`);
  }
  if (!header.kid) throw new Error("Token has no key id");

  const jwk = await keyFor(header.kid);
  if (!jwk) throw new Error(`Unknown signing key: ${header.kid}`);

  const key = await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );

  // Check 1: the signature itself, over the exact signed input.
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    decodeSegment(signatureSegment),
    new TextEncoder().encode(`${headerSegment}.${payloadSegment}`),
  );

  if (!valid) throw new Error("Signature does not verify");

  const payload = decodeJson(payloadSegment) as {
    aud?: string;
    iss?: string;
    sub?: string;
    exp?: number;
    iat?: number;
    phone_number?: string;
  };

  const now = Math.floor(Date.now() / 1000);

  // Check 3: minted for OUR project, not one the attacker controls.
  if (payload.aud !== FIREBASE_PROJECT_ID) {
    throw new Error(`Wrong audience: ${payload.aud}`);
  }

  // Check 4.
  if (payload.iss !== `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`) {
    throw new Error(`Wrong issuer: ${payload.iss}`);
  }

  // Check 5.
  if (typeof payload.exp !== "number" || payload.exp + CLOCK_SKEW < now) {
    throw new Error("Token has expired");
  }
  if (typeof payload.iat !== "number" || payload.iat - CLOCK_SKEW > now) {
    throw new Error("Token was issued in the future");
  }

  if (!payload.sub) throw new Error("Token has no subject");

  return { uid: payload.sub, phone: payload.phone_number ?? null };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    // WHO is claiming the number - from their own SUGO session, never from the
    // request body. The Firebase token says which number was verified; this
    // says which account it belongs to.
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    if (!FIREBASE_PROJECT_ID) {
      // A configuration fault, and worth naming: without it every token would
      // fail the audience check and the error would look like a bad token.
      return fail(
        "Phone verification is not configured on the server yet.",
        500,
        "FIREBASE_PROJECT_ID is not set",
      );
    }

    const body = await readJson<VerifyRequest>(req);
    const idToken = (body.id_token ?? "").trim();

    if (!idToken) return fail("id_token is required", 422);

    let verified: VerifiedToken;
    try {
      verified = await verifyIdToken(idToken);
    } catch (error) {
      // Logged in full, reported generically. See `verifyIdToken`.
      console.warn(
        `verify-firebase-phone: rejected token for ${uid} - ${(error as Error).message}`,
      );
      return fail("That verification could not be confirmed.", 401);
    }

    // Check 6: a Firebase user without a phone claim is a valid user who has
    // verified nothing relevant here.
    if (!verified.phone) {
      return fail("That sign-in did not verify a phone number.", 422);
    }

    const db = serviceClient();

    const { data, error } = await db.rpc("set_phone_verified", {
      p_user_id: uid,
      p_phone: verified.phone,
    });

    if (error) {
      return fail("Could not save your verified number", 500, error.message);
    }

    console.log(
      `verify-firebase-phone: ${uid} verified via firebase uid ${verified.uid}`,
    );

    return json(data ?? { phone_verified: true, phone: verified.phone });
  } catch (error) {
    return fail(
      "Could not confirm your phone number",
      500,
      (error as Error).message,
    );
  }
});
