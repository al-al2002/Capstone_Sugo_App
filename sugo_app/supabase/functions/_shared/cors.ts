/**
 * CORS headers shared by every SUGO edge function.
 *
 * A Flutter mobile build does not send a preflight, but Flutter Web does, and
 * so does `curl -i` when you are debugging. Answering OPTIONS costs one line
 * per function and removes a whole category of "it works in Postman but not in
 * the app" confusion.
 */
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  // GET is here for `traffic-tile`, which serves map tiles; everything else
  // is POST.
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

/** JSON response with CORS applied. */
export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Error response in one consistent shape: `{ error, detail? }`. */
export function fail(message: string, status = 400, detail?: unknown): Response {
  console.error(`[${status}] ${message}`, detail ?? "");
  return json({ error: message, detail: detail ?? null }, status);
}

/** Standard preflight answer. Return this for `req.method === "OPTIONS"`. */
export function preflight(): Response {
  return new Response("ok", { headers: corsHeaders });
}
