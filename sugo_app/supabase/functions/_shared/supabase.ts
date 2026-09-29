/**
 * Two Supabase clients, for two very different jobs.
 *
 * ## Why there are two
 *
 * `serviceClient()` uses `SUPABASE_SERVICE_ROLE_KEY`, which **ignores every RLS
 * policy**. RB-CARS cannot work without it: to rank technicians the matcher has
 * to read all of them, while the `technicians_select_own` policy lets a normal
 * user read exactly one row - their own.
 *
 * That power is also the risk. So no function here ever acts on a service
 * client without first establishing who is asking, via `callerId()`, and
 * checking that person actually owns the row being touched. The pattern is:
 *
 * ```ts
 * const uid = await callerId(req);              // who are you, per your JWT
 * const db  = serviceClient();                  // elevated read/write
 * const job = await db.from("jobs")...          // fetch the row
 * if (job.client_id !== uid) return fail(...);  // prove ownership, then act
 * ```
 *
 * Elevated privilege plus an explicit ownership check. Never elevated
 * privilege alone.
 */
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

/** Injected by Supabase into every deployed function. Never set by hand. */
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

/** Elevated client. Bypasses RLS. Pair every use with an ownership check. */
export function serviceClient(): SupabaseClient {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    throw new Error(
      "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing from the function environment",
    );
  }
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * Resolves the signed-in user from the request's `Authorization` header.
 *
 * `supabase.functions.invoke()` attaches the caller's access token
 * automatically, so this is the identity of whoever tapped the button in the
 * app. Returns null when the header is absent, malformed or expired.
 */
export async function callerId(req: Request): Promise<string | null> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;

  // The anon key is enough here; we are only asking GoTrue to validate a JWT.
  const client = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await client.auth.getUser();
  if (error) {
    console.warn("callerId: token rejected", error.message);
    return null;
  }
  return data.user?.id ?? null;
}

/**
 * True when the request carries the service role key directly, i.e. it came
 * from pg_cron or an operator's curl rather than from a user's phone. Used by
 * `aggregate-outcomes`, which has no human caller.
 */
export function isServiceRequest(req: Request): boolean {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  return Boolean(SERVICE_ROLE_KEY) && token === SERVICE_ROLE_KEY;
}

/** Parses a JSON body, returning `{}` rather than throwing on empty input. */
export async function readJson<T>(req: Request): Promise<T> {
  try {
    const text = await req.text();
    if (!text.trim()) return {} as T;
    return JSON.parse(text) as T;
  } catch (_error) {
    return {} as T;
  }
}
