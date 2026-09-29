/**
 * Issues a one-time code for phone verification, and sends it by SMS.
 *
 * ```
 * POST /functions/v1/send-phone-code
 * { "phone": "+639171234567" }
 *
 * -> { expires_at, delivery: "sms" | "demo", debug_code? }
 * ```
 *
 * ## Providers
 *
 * Chosen by the `SMS_PROVIDER` secret:
 *
 *   semaphore  - Philippine gateway, billed in pesos. Needs SEMAPHORE_API_KEY.
 *                The usual choice here: no per-country surcharge, and sender
 *                names are approved locally.
 *   twilio     - Needs TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM.
 *                Works everywhere, billed in USD.
 *   (unset)    - DEMO MODE. No SMS is sent and the code comes back in the
 *                response so the flow can be completed without an account.
 *
 * Set them with:
 *   supabase secrets set SMS_PROVIDER=semaphore SEMAPHORE_API_KEY=...
 *
 * ## Demo mode is honest, not hidden
 *
 * `delivery` tells the app which happened, so it can say "no SMS was sent,
 * here is your code" rather than leaving someone waiting for a text that will
 * never arrive. Everything else about the flow is real in both modes: the code
 * is CSPRNG-generated, stored server-side with an expiry, single-use, rate
 * limited, and checked by `verify_phone_code()` where the client cannot read
 * it.
 *
 * What demo mode is NOT is secure. A code returned to the caller verifies
 * nothing about who holds the phone. Configure a provider before this faces
 * real users.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, readJson, serviceClient } from "../_shared/supabase.ts";

/** Digits in a code. Six is the SMS convention users expect. */
const CODE_LENGTH = 6;

/**
 * How many codes one account may request per hour.
 *
 * Each SMS costs money and every request is a message to a number the
 * requester may not own, so an unthrottled endpoint is both a bill and a way
 * to harass a stranger's phone. Five leaves room for a genuine "I did not get
 * it" retry loop.
 */
const MAX_CODES_PER_HOUR = 5;

const SMS_PROVIDER = (Deno.env.get("SMS_PROVIDER") ?? "").trim().toLowerCase();
const DEMO_MODE = SMS_PROVIDER === "";

interface SendRequest {
  phone?: string;
}

/**
 * Normalises a Philippine mobile number to E.164.
 *
 * Repeated from the Dart side deliberately. The client-side copy exists to put
 * an error under the field as the user types; this one exists because a
 * client-side check is a convenience and never a guarantee.
 */
function normalizePhone(input: string): string | null {
  const digits = input.replace(/[^0-9+]/g, "");

  if (/^\+639\d{9}$/.test(digits)) return digits;
  if (/^639\d{9}$/.test(digits)) return `+${digits}`;
  if (/^09\d{9}$/.test(digits)) return `+63${digits.slice(1)}`;
  if (/^9\d{9}$/.test(digits)) return `+63${digits}`;

  return null;
}

/**
 * Generates a code with `crypto.getRandomValues`, not `Math.random`.
 *
 * `Math.random` is not a cryptographic generator: its output is predictable
 * from previous values, so an attacker who watched a few codes could narrow
 * the next one to a handful of guesses - well within the five attempts the
 * verify step allows.
 *
 * The rejection loop avoids modulo bias.
 */
function generateCode(): string {
  const max = 10 ** CODE_LENGTH;
  const limit = Math.floor(0xffffffff / max) * max;

  const buffer = new Uint32Array(1);
  let value: number;
  do {
    crypto.getRandomValues(buffer);
    value = buffer[0];
  } while (value >= limit);

  return String(value % max).padStart(CODE_LENGTH, "0");
}

function messageFor(code: string): string {
  // Short and unambiguous. The app name is included because a bare six-digit
  // code from an unknown sender reads as spam.
  return `${code} is your SUGO verification code. It expires in 10 minutes. ` +
    `Do not share it with anyone.`;
}

interface SendResult {
  sent: boolean;
  detail?: string;
}

/** Semaphore (semaphore.co) - the usual Philippine gateway. */
async function sendViaSemaphore(phone: string, code: string): Promise<SendResult> {
  const apiKey = Deno.env.get("SEMAPHORE_API_KEY");
  if (!apiKey) {
    return { sent: false, detail: "SEMAPHORE_API_KEY is not set" };
  }

  const body = new URLSearchParams({
    apikey: apiKey,
    // Semaphore accepts local or E.164; E.164 is unambiguous.
    number: phone,
    message: messageFor(code),
  });

  // Optional and must be pre-approved by Semaphore. Without it they send from
  // the shared "SEMAPHORE" sender name, which still works.
  const sender = Deno.env.get("SEMAPHORE_SENDER_NAME");
  if (sender) body.set("sendername", sender);

  try {
    const response = await fetch("https://api.semaphore.co/api/v4/messages", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    });

    const text = await response.text();

    if (!response.ok) {
      return { sent: false, detail: `Semaphore ${response.status}: ${text.slice(0, 200)}` };
    }

    // Semaphore returns an array of message objects. A rejected number still
    // comes back 200 with a status of "Failed", so the body has to be read
    // rather than trusting the HTTP code.
    try {
      const parsed = JSON.parse(text);
      const first = Array.isArray(parsed) ? parsed[0] : parsed;
      const status = String(first?.status ?? "").toLowerCase();

      if (status === "failed") {
        return { sent: false, detail: `Semaphore rejected the message: ${text.slice(0, 200)}` };
      }
    } catch {
      // Unparseable but 200. Treat as sent rather than blocking the user on a
      // response-format change.
    }

    return { sent: true };
  } catch (error) {
    return { sent: false, detail: `Semaphore unreachable: ${(error as Error).message}` };
  }
}

/** Twilio, for deployments outside the Philippines. */
async function sendViaTwilio(phone: string, code: string): Promise<SendResult> {
  const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const token = Deno.env.get("TWILIO_AUTH_TOKEN");
  const from = Deno.env.get("TWILIO_FROM");

  if (!sid || !token || !from) {
    return {
      sent: false,
      detail: "TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN or TWILIO_FROM is not set",
    };
  }

  try {
    const response = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`,
      {
        method: "POST",
        headers: {
          Authorization: `Basic ${btoa(`${sid}:${token}`)}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({ To: phone, From: from, Body: messageFor(code) }),
      },
    );

    if (!response.ok) {
      const text = await response.text();
      return { sent: false, detail: `Twilio ${response.status}: ${text.slice(0, 200)}` };
    }

    return { sent: true };
  } catch (error) {
    return { sent: false, detail: `Twilio unreachable: ${(error as Error).message}` };
  }
}

/**
 * Hands the code to whichever gateway is configured.
 *
 * The code is never logged. It is a live credential until it is consumed, and
 * function logs are retained and readable by anyone with project access.
 */
async function sendSms(phone: string, code: string): Promise<SendResult> {
  switch (SMS_PROVIDER) {
    case "semaphore":
      return sendViaSemaphore(phone, code);
    case "twilio":
      return sendViaTwilio(phone, code);
    case "":
      return { sent: true, detail: "demo" };
    default:
      return { sent: false, detail: `Unknown SMS_PROVIDER "${SMS_PROVIDER}"` };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const body = await readJson<SendRequest>(req);
    const phone = normalizePhone(body.phone ?? "");

    if (!phone) {
      return fail(
        "Enter a valid Philippine mobile number, like 0917 123 4567",
        422,
      );
    }

    const db = serviceClient();

    // --------------------------------------------------------- rate limit
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count, error: countError } = await db
      .from("phone_verifications")
      .select("id", { count: "exact", head: true })
      .eq("user_id", uid)
      .gte("created_at", since);

    if (countError) {
      return fail("Could not send the code", 500, countError.message);
    }
    if ((count ?? 0) >= MAX_CODES_PER_HOUR) {
      return fail("Too many codes requested. Try again in an hour.", 429);
    }

    // -------------------------------------------------------- issue + send
    const code = generateCode();

    // Stored before sending. If the send then fails the row is simply unused
    // and expires; sending first and failing to store would put a code in
    // someone's hand that the server cannot recognise.
    const { data, error } = await db.rpc("issue_phone_code", {
      p_user_id: uid,
      p_phone: phone,
      p_code: code,
    });

    if (error) {
      return fail("Could not send the code", 500, error.message);
    }

    const result = await sendSms(phone, code);

    if (!result.sent) {
      // Named rather than generic: a missing key and an unreachable gateway
      // need different fixes, and "could not send" sends the operator hunting
      // in the wrong place.
      console.error(`send-phone-code: delivery failed - ${result.detail}`);
      return fail(
        "Could not send the code by SMS right now. Please try again shortly.",
        502,
        result.detail,
      );
    }

    console.log(
      `send-phone-code: issued for ${uid} via ${DEMO_MODE ? "demo" : SMS_PROVIDER}`,
    );

    return json({
      expires_at: (data as { expires_at?: string } | null)?.expires_at ?? null,
      // Tells the app what actually happened, so it can show the code instead
      // of leaving someone waiting for a text that is never coming.
      delivery: DEMO_MODE ? "demo" : "sms",
      ...(DEMO_MODE ? { debug_code: code } : {}),
    });
  } catch (error) {
    return fail("Could not send the code", 500, (error as Error).message);
  }
});
