/**
 * TomTom traffic-flow tiles, proxied so the key never leaves the server.
 *
 * ```
 * GET /functions/v1/traffic-tile?z=14&x=13733&y=7981
 * -> image/png
 * ```
 *
 * ## Why a proxy and not a direct tile URL
 *
 * `app_env.dart` already draws the line this function defends: the MapTiler key
 * ships in the client because "the phone itself downloads the tiles, so there is
 * nowhere to hide it", while "the TomTom and OpenWeatherMap keys live as
 * Supabase secrets because only the edge function ever calls them".
 *
 * Pointing a `TileLayer` straight at `api.tomtom.com` would have moved
 * `TOMTOM_API_KEY` into the APK and made that second sentence false - and the
 * same key is what Stage 2 scoring depends on, so leaking it is not just a
 * quota problem. Proxying keeps the stated architecture true: the device asks
 * Supabase for a tile, Supabase asks TomTom, and the key stays put.
 *
 * ## The cost, stated plainly
 *
 * This is the trade. A direct URL costs nothing; every tile through here is an
 * edge-function invocation. A phone-sized map is roughly 6-9 tiles per view, and
 * panning a delivery route might reach 100-150 in a session. Against Supabase's
 * 500k free invocations that is thousands of tracking sessions, which is ample
 * for a capstone - but it is why the overlay is behind a toggle rather than on
 * by default, and why the response is aggressively cacheable.
 *
 * ## Style
 *
 * `relative` colours each road by its speed relative to free-flow, which is the
 * "is it slow right now" read a waiting client wants. The matcher separately
 * calls `flowSegmentData/absolute` for a numeric congestion ratio - different
 * question, different endpoint, same key.
 */
import { corsHeaders, fail, preflight } from "../_shared/cors.ts";
import { callerId } from "../_shared/supabase.ts";

/** TomTom serves flow tiles up to z22. */
const MAX_ZOOM = 22;

/** Traffic moves; a stale tile is misleading. Two minutes is TomTom's own
 * refresh cadence, so caching longer would show conditions that no longer
 * exist while caching less would just burn quota redrawing the same picture. */
const CACHE_SECONDS = 120;

const TILE_TIMEOUT_MS = 6000;

/** Parses and range-checks one tile coordinate. */
function tileParam(value: string | null, max: number): number | null {
  if (value === null) return null;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed >= max) return null;
  return parsed;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "GET") return fail("Use GET", 405);

  try {
    // An authenticated user, not merely anyone holding the publishable key.
    // Without this the proxy would be an open TomTom relay for anybody who
    // pulled the anon key out of the APK - which is the very thing the proxy
    // exists to prevent, one step removed.
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const key = Deno.env.get("TOMTOM_API_KEY");
    if (!key) {
      console.warn("TOMTOM_API_KEY is not set; traffic overlay unavailable");
      return fail("Traffic layer is not configured", 503);
    }

    const url = new URL(req.url);
    const z = tileParam(url.searchParams.get("z"), MAX_ZOOM + 1);
    if (z === null) return fail("z is out of range", 422);

    // x and y are bounded by the zoom level: 2^z tiles per axis. Checking this
    // stops the proxy being pointed at arbitrary upstream paths.
    const axis = 2 ** z;
    const x = tileParam(url.searchParams.get("x"), axis);
    const y = tileParam(url.searchParams.get("y"), axis);
    if (x === null || y === null) return fail("x or y is out of range", 422);

    const upstream =
      `https://api.tomtom.com/traffic/map/4/tile/flow/relative/${z}/${x}/${y}.png` +
      `?key=${key}`;

    const response = await fetch(upstream, {
      signal: AbortSignal.timeout(TILE_TIMEOUT_MS),
    });

    if (!response.ok) {
      console.warn(`TomTom tile ${z}/${x}/${y} returned ${response.status}`);
      // 204 rather than an error status: flutter_map treats a failed tile as a
      // broken image and retries it. An empty tile just leaves the base map
      // showing, which is the correct degraded state for an optional overlay.
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    return new Response(response.body, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "image/png",
        "Cache-Control": `public, max-age=${CACHE_SECONDS}`,
      },
    });
  } catch (error) {
    console.warn("traffic tile failed", (error as Error).message);
    return new Response(null, { status: 204, headers: corsHeaders });
  }
});
