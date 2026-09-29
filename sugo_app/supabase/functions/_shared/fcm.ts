/**
 * Firebase Cloud Messaging sender.
 *
 * ## Why a service account and not a server key
 *
 * FCM's legacy `Authorization: key=...` endpoint is retired. HTTP v1 requires an
 * OAuth2 access token minted from a Google service account, so this file signs
 * a JWT with the account's private key and exchanges it for one. There is no
 * simpler credential available - the extra ~60 lines below are that migration,
 * not over-engineering.
 *
 * ## Setup this expects
 *
 * `FIREBASE_SERVICE_ACCOUNT` - the whole downloaded JSON, as one secret:
 *
 * ```sh
 * npx supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
 * ```
 *
 * Absent, [sendPush] returns `configured: false` and sends nothing. That is the
 * same graceful-degradation rule the TomTom and OpenWeatherMap clients follow:
 * a missing key disables a feature, it never breaks the caller.
 */

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
  token_uri?: string;
}

export interface PushMessage {
  title: string;
  body: string;
  /** Delivered alongside the notification for the app to route on. */
  data?: Record<string, string>;
}

export interface PushResult {
  configured: boolean;
  sent: number;
  /** Tokens FCM rejected as dead. The caller should delete these. */
  stale: string[];
}

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const DEFAULT_TOKEN_URI = "https://oauth2.googleapis.com/token";

/**
 * Cached access token, module-scoped.
 *
 * An edge-function isolate is reused across invocations, so caching the hour-
 * long token here means a burst of notifications does not re-sign a JWT and
 * round-trip to Google every time. Refreshed a minute early so an in-flight
 * request cannot land on an expired one.
 */
let cachedToken: { value: string; expiresAt: number } | null = null;

function readServiceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) return null;

  try {
    const parsed = JSON.parse(raw) as ServiceAccount;
    if (!parsed.client_email || !parsed.private_key || !parsed.project_id) {
      console.warn("FIREBASE_SERVICE_ACCOUNT is missing required fields");
      return null;
    }
    return parsed;
  } catch {
    console.warn("FIREBASE_SERVICE_ACCOUNT is not valid JSON");
    return null;
  }
}

const base64Url = (bytes: Uint8Array): string =>
  btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

/**
 * PEM (PKCS#8) to the raw DER bytes Web Crypto wants.
 *
 * Typed `Uint8Array<ArrayBuffer>`, not bare `Uint8Array`: newer TypeScript
 * widens the bare form to any buffer (shared ones included), which
 * `importKey` refuses at type-check time. The bytes are the same either way.
 */
function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    // The secret arrives with literal \n when set from a shell, and real
    // newlines when set from a file. Both have to work.
    .replace(/\\n/g, "")
    .replace(/\s/g, "");

  const binary = atob(body);
  const der = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) der[i] = binary.charCodeAt(i);
  return der;
}

/** Signs the assertion JWT and exchanges it for an OAuth2 access token. */
async function accessTokenFor(account: ServiceAccount): Promise<string | null> {
  if (cachedToken && cachedToken.expiresAt > Date.now()) {
    return cachedToken.value;
  }

  const tokenUri = account.token_uri ?? DEFAULT_TOKEN_URI;
  const issuedAt = Math.floor(Date.now() / 1000);
  const expiresAt = issuedAt + 3600;

  const encoder = new TextEncoder();
  const header = base64Url(
    encoder.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const claims = base64Url(
    encoder.encode(
      JSON.stringify({
        iss: account.client_email,
        scope: SCOPE,
        aud: tokenUri,
        iat: issuedAt,
        exp: expiresAt,
      }),
    ),
  );

  try {
    const key = await crypto.subtle.importKey(
      "pkcs8",
      pemToDer(account.private_key),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );

    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      encoder.encode(`${header}.${claims}`),
    );

    const assertion =
      `${header}.${claims}.${base64Url(new Uint8Array(signature))}`;

    const response = await fetch(tokenUri, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    });

    if (!response.ok) {
      console.warn(`FCM token exchange returned ${response.status}`);
      return null;
    }

    const body = (await response.json()) as { access_token?: string };
    if (!body.access_token) return null;

    // A minute of headroom, so a request that starts just before expiry still
    // arrives with a valid token.
    cachedToken = {
      value: body.access_token,
      expiresAt: Date.now() + 3540_000,
    };
    return body.access_token;
  } catch (error) {
    console.warn("FCM token exchange failed", (error as Error).message);
    return null;
  }
}

/**
 * Sends one notification to every token given.
 *
 * Reports which tokens FCM considered dead rather than deleting them here: this
 * module has no database client, and the caller already has one.
 */
export async function sendPush(
  tokens: string[],
  message: PushMessage,
): Promise<PushResult> {
  const account = readServiceAccount();
  if (!account) {
    console.warn("FIREBASE_SERVICE_ACCOUNT is not set; push is disabled");
    return { configured: false, sent: 0, stale: [] };
  }
  if (tokens.length === 0) {
    return { configured: true, sent: 0, stale: [] };
  }

  const token = await accessTokenFor(account);
  if (!token) return { configured: true, sent: 0, stale: [] };

  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;

  let sent = 0;
  const stale: string[] = [];

  // HTTP v1 has no true multicast, so this is one request per device. A client
  // has one or two, which is why a simple loop is right here and a batch API
  // would be premature.
  await Promise.all(
    tokens.map(async (deviceToken) => {
      try {
        const response = await fetch(endpoint, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: deviceToken,
              notification: { title: message.title, body: message.body },
              data: message.data ?? {},
              // A delay is time-critical: it is worth waking a dozing handset,
              // because a notification that lands after arrival is pointless.
              android: { priority: "HIGH" },
            },
          }),
        });

        if (response.ok) {
          sent += 1;
          return;
        }

        // Deciding what counts as a dead token, carefully.
        //
        // 404 is unambiguous: the install is gone.
        //
        // 400 INVALID_ARGUMENT is NOT. FCM returns it both for a bad
        // registration token AND for a malformed message - so treating every
        // 400 as a dead token would mean that one day someone changes this
        // payload, every send 400s, and this function deletes the entire
        // device_tokens table in response to its own bug.
        //
        // So a 400 only counts when FCM actually names the token as the
        // problem. Anything else is our fault and is logged, not cleaned up.
        const body = await response.text();

        if (
          response.status === 404 ||
          (response.status === 400 && /registration token/i.test(body))
        ) {
          stale.push(deviceToken);
        }
        console.warn(`FCM send returned ${response.status}: ${body.slice(0, 200)}`);
      } catch (error) {
        console.warn("FCM send failed", (error as Error).message);
      }
    }),
  );

  return { configured: true, sent, stale };
}
