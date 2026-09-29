/**
 * Public technician directory.
 *
 * ```
 * POST /functions/v1/technician-directory
 * { "action": "list", "limit": 10, "device_type": "laptop" }
 * { "action": "get",  "technician_id": "uuid" }
 * ```
 *
 * ## Why this function has to exist
 *
 * `technicians_select_own` restricts the table to `id = auth.uid()`. That is
 * the right policy - a client has no business enumerating the whole workforce
 * with an anon key - but the home screen still needs a "Recommended
 * technicians" row, and the detail screen still needs one technician's profile.
 *
 * So the directory is a deliberate, narrow hole in that wall: it runs on the
 * service role, requires a signed-in caller, returns only verified technicians,
 * and strips the fields a browsing client has no reason to see.
 *
 * ## What is withheld
 *
 * `phone` is released only when the caller has an actual booking with that
 * technician - a job of theirs where `assigned_technician_id` matches and the
 * status is confirmed or in progress. Browsing the directory never exposes a
 * contact number. `current_workload` is likewise internal: it is a scoring
 * input, not something to publish on a profile card.
 *
 * A technician's own `latitude`/`longitude` are read here but never returned.
 * The caller sends its own coordinates and gets back a `distance_km` per
 * technician instead, so the card can say "1.2 km away" without the app ever
 * holding the home address of someone it has not booked.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, readJson, serviceClient } from "../_shared/supabase.ts";
// Single-sourced with the matcher rather than copied: two haversines that
// disagree would put a different distance on the card than on the match score.
import { distanceBetween } from "../match-technician/scoring/geo.ts";

interface DirectoryRequest {
  action?: "list" | "get";
  technician_id?: string;
  device_type?: string;
  limit?: number;
  /** Caller's position, so the reply can carry a distance. Both or neither. */
  latitude?: number | null;
  longitude?: number | null;
}

/** Where the caller is, when they were willing and able to say. */
interface Origin {
  latitude: number;
  longitude: number;
}

function readOrigin(body: DirectoryRequest): Origin | null {
  const { latitude, longitude } = body;
  if (typeof latitude !== "number" || typeof longitude !== "number") {
    return null;
  }
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  return { latitude, longitude };
}

interface TechnicianRow {
  id: string;
  skill_tags: string[] | null;
  tier: string;
  specialization: string[] | null;
  is_verified: boolean;
  badge: string | null;
  rating: number | null;
  total_jobs: number | null;
  created_at: string | null;
  // Registration writes `base_latitude`/`base_longitude`; the older
  // `latitude`/`longitude` pair is left over from before service areas existed
  // and is null on every account created since. Both are read so an old row
  // still resolves - the same fallback the matcher uses in scoring/engine.ts.
  base_latitude: number | null;
  base_longitude: number | null;
  latitude: number | null;
  longitude: number | null;
  profiles?: {
    full_name: string | null;
    avatar_url: string | null;
    phone: string | null;
  } | null;
}

// The coordinate columns are selected but never emitted - see toPublic.
const PUBLIC_COLUMNS =
  "id, skill_tags, tier, specialization, is_verified, badge, rating, " +
  "total_jobs, created_at, base_latitude, base_longitude, " +
  "latitude, longitude, profiles!inner(full_name, avatar_url, phone)";

const MAX_LIMIT = 50;
const DEFAULT_LIMIT = 12;

/** Flattens the joined row and drops anything a browser should not receive. */
function toPublic(
  row: TechnicianRow,
  includePhone: boolean,
  origin: Origin | null,
) {
  const distanceKm = origin
    ? distanceBetween(
      origin.latitude,
      origin.longitude,
      row.base_latitude ?? row.latitude,
      row.base_longitude ?? row.longitude,
    )
    : null;

  return {
    id: row.id,
    full_name: row.profiles?.full_name ?? null,
    avatar_url: row.profiles?.avatar_url ?? null,
    phone: includePhone ? row.profiles?.phone ?? null : null,
    tier: row.tier,
    badge: row.badge,
    is_verified: row.is_verified,
    rating: row.rating ?? 0,
    total_jobs: row.total_jobs ?? 0,
    specialization: row.specialization ?? [],
    skill_tags: row.skill_tags ?? [],
    created_at: row.created_at,
    // Rounded to 10 m. Coarse enough not to pinpoint an address, fine enough
    // that a technician 106 m away is not flattened to 0.1 km and then
    // rendered as "100 m" - or, under 50 m, as "0 m".
    distance_km: distanceKm === null ? null : Math.round(distanceKm * 100) / 100,
    // current_workload and the raw latitude/longitude are intentionally
    // absent: scoring inputs and a home address, not profile fields.
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const body = await readJson<DirectoryRequest>(req);
    const action = body.action ?? "list";
    const origin = readOrigin(body);
    const db = serviceClient();

    // ------------------------------------------------------------------ get
    if (action === "get") {
      const technicianId = body.technician_id;
      if (!technicianId) return fail("technician_id is required", 422);

      const { data, error } = await db
        .from("technicians")
        .select(PUBLIC_COLUMNS)
        .eq("id", technicianId)
        .maybeSingle<TechnicianRow>();

      if (error) return fail("Could not load technician", 500, error.message);
      if (!data) return fail("Technician not found", 404);

      // Release the contact number only to a client who actually booked them.
      const { count } = await db
        .from("jobs")
        .select("id", { count: "exact", head: true })
        .eq("client_id", uid)
        .eq("assigned_technician_id", technicianId)
        .in("status", ["confirmed", "in_progress", "completed"]);

      const hasBooking = (count ?? 0) > 0;

      return json({
        technician: toPublic(data, hasBooking, origin),
        contact_unlocked: hasBooking,
      });
    }

    // ----------------------------------------------------------------- list
    const limit = Math.min(
      Math.max(body.limit ?? DEFAULT_LIMIT, 1),
      MAX_LIMIT,
    );

    let query = db
      .from("technicians")
      .select(PUBLIC_COLUMNS)
      .eq("is_verified", true);

    // `contains` maps to the Postgres array operator @>, so this asks for
    // technicians whose specialization array holds this device type.
    if (body.device_type) {
      query = query.contains("specialization", [body.device_type]);
    }

    const { data, error } = await query
      .order("rating", { ascending: false })
      .order("total_jobs", { ascending: false })
      .limit(limit)
      .returns<TechnicianRow[]>();

    if (error) return fail("Could not load technicians", 500, error.message);

    // Nearest first once a distance is known. The ranking above it - rating,
    // then job count - still decides who is in the list; this only reorders
    // what came back, so a highly-rated technician two streets away is not
    // buried under an equally-rated one across the city.
    const technicians = (data ?? []).map((row) => toPublic(row, false, origin));

    if (origin) {
      technicians.sort((a, b) => {
        if (a.distance_km === null) return b.distance_km === null ? 0 : 1;
        if (b.distance_km === null) return -1;
        return a.distance_km - b.distance_km;
      });
    }

    return json({ technicians });
  } catch (error) {
    return fail("Directory lookup failed", 500, (error as Error).message);
  }
});
