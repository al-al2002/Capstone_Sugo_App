/**
 * A driving route to a job's destination, drawn inside the app.
 *
 * ```
 * POST /functions/v1/job-route
 * { "job_id": "uuid", "origin_latitude": 7.07, "origin_longitude": 125.61 }
 * ```
 *
 * ## Why this exists
 *
 * "Get directions" used to hand the coordinates to Google Maps and leave the
 * app. The brief is that routing stays in SUGO, and `flutter_map` can draw a
 * line but cannot work out which roads it should follow. So the road geometry
 * comes from TomTom's Routing API and the app draws it.
 *
 * TomTom rather than another provider because `TOMTOM_API_KEY` is already a
 * Supabase secret, already trusted by the matcher and the traffic overlay, and
 * its routes use live traffic - so the ETA on the route screen agrees with the
 * traffic the rest of the app already shows.
 *
 * ## Why the caller sends only an origin
 *
 * The origin has to come from the device: it is wherever the user is standing.
 * The DESTINATION does not, and is resolved here from the job. Accepting both
 * ends from the app would turn this into a free TomTom routing service for
 * anyone signed in, spending the same key the matcher runs on. Tied to a job,
 * a user can only route to a place their own booking entitles them to.
 *
 * Journeys supported, by who is travelling:
 *
 *   * the assigned TECHNICIAN, on a home-service job -> the client's address;
 *   * the assigned TECHNICIAN, on a pickup job -> the client's address, on
 *     both legs: going to collect the unit, and taking it back afterwards
 *     when the client asked for it to be delivered. Refused in between,
 *     because the unit is on a bench and nobody is driving anywhere;
 *   * the CLIENT, once the unit is `ready_for_collection` -> the workshop, or
 *     as soon as they have chosen to collect it themselves
 *     (`job_return_preferences`, 20260922000005).
 *
 * The technician's pickup legs were added with the negotiation/return work on
 * 2026-09-23. Before that a pickup job had no technician routing at all: the
 * check was `service_path !== "home_service" -> refuse`, so the one person who
 * actually had to drive to an address was the one the app would not navigate.
 *
 * ## Live mode: the trip that is happening now (2026-09-29)
 *
 * ```
 * POST /functions/v1/job-route
 * { "job_id": "uuid", "live": true }
 * ```
 *
 * The tracking maps used to draw a straight dotted line between whoever was
 * travelling and where they were going. Live mode returns the road route for
 * the leg in progress instead, so the person WATCHING - the client following
 * a technician, or a technician waiting for a client to arrive - sees the
 * streets being driven.
 *
 * No origin is taken from the caller: it is the traveller's last reported
 * position in `job_tracking` (the technician's, or on `ready_for_collection`
 * the client's own trip columns), and the destination comes from
 * `_shared/leg_destination.ts` - the same place the ETA counts down to. Either
 * person on the job may ask, and only while a leg is actually moving.
 *
 * The app asks again only when the traveller drifts well off the drawn route
 * or the stage changes, not per GPS fix - see `TrackingMap`.
 *
 * ## Why the workshop never falls back to a live position
 *
 * Shop coordinates, then the registered base, and then nothing. The
 * technician's live `latitude`/`longitude` is excluded on purpose: during a
 * working day it is someone else's house, and a route that ends there would
 * disclose it just as surely as printing the coordinates would. This is the
 * same rule 20260916000008 applies to `technician_profile`.
 *
 * ## Cost
 *
 * One TomTom call when the route screen opens, and a recalculation only when
 * the user has left the drawn route - throttled on the device to once a
 * minute. A twenty-minute trip with a couple of wrong turns is a handful of
 * calls, not one per GPS fix.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, readJson, serviceClient } from "../_shared/supabase.ts";
import { haversineKm } from "../match-technician/scoring/geo.ts";
import { resolveLegDestination } from "../_shared/leg_destination.ts";

interface RouteRequest {
  job_id?: string;
  origin_latitude?: number;
  origin_longitude?: number;
  /** Route the leg in progress, from the traveller's last position. */
  live?: boolean;
}

/** The technician's legs that move. `in_repair` and `delivered` do not. */
const LIVE_TECHNICIAN_STAGES = new Set([
  "heading_to_pickup",
  "collected",
  "returning_to_shop",
  "out_for_delivery",
]);

/** The one leg the client travels: coming to collect (20260929000001). */
const CLIENT_TRIP_STAGE = "ready_for_collection";

/**
 * Car, not motorcycle. TomTom documents `motorcycle` as BETA, and a capstone
 * demo is the wrong place to depend on beta routing. Over city roads the two
 * choose near-identical paths; the gap is lanes and filtering, not streets.
 */
const TRAVEL_MODE = "car";

/** Routing does more work than a flow sample, so it gets more time. */
const ROUTE_TIMEOUT_MS = 8000;

/**
 * Straight-line ceiling for a route request.
 *
 * SUGO works a city, with service radii measured in tens of kilometres. An
 * origin hundreds of kilometres away is a GPS glitch or a spoofed request, and
 * routing it would return an enormous polyline to draw nothing useful.
 */
const MAX_ROUTE_KM = 150;

/**
 * Upper bound on points sent to the phone. A cross-city TomTom route is a few
 * hundred points; this only thins pathological responses so a slow handset is
 * not asked to draw thousands of segments for a line a few pixels wide.
 */
const MAX_POINTS = 1500;

function validCoordinate(lat: unknown, lng: unknown): lat is number {
  return typeof lat === "number" && typeof lng === "number" &&
    Number.isFinite(lat) && Number.isFinite(lng) &&
    lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const body = await readJson<RouteRequest>(req);
    const jobId = body.job_id;
    if (!jobId) return fail("job_id is required", 422);

    const db = serviceClient();

    const { data: job, error: jobError } = await db
      .from("jobs")
      .select(
        "id, client_id, assigned_technician_id, service_path, status, " +
          "latitude, longitude",
      )
      .eq("id", jobId)
      .maybeSingle<{
        id: string;
        client_id: string;
        assigned_technician_id: string | null;
        service_path: string | null;
        status: string;
        latitude: number | null;
        longitude: number | null;
      }>();

    if (jobError) return fail("Could not load the job", 500, jobError.message);
    if (!job) return fail("Job not found", 404);

    // ------------------------------------------------------------- live
    if (body.live === true) {
      if (uid !== job.client_id && uid !== job.assigned_technician_id) {
        return fail("This job belongs to someone else", 403);
      }

      const { data: leg } = await db
        .from("job_tracking")
        .select(
          "stage, latitude, longitude, client_latitude, client_longitude, " +
            "client_trip_started_at, client_arrived_at",
        )
        .eq("job_id", jobId)
        .maybeSingle<{
          stage: string;
          latitude: number | null;
          longitude: number | null;
          client_latitude: number | null;
          client_longitude: number | null;
          client_trip_started_at: string | null;
          client_arrived_at: string | null;
        }>();

      if (!leg) return json({ available: false, reason: "not_travelling" });

      const clientTrip = leg.stage === CLIENT_TRIP_STAGE;
      const moving = clientTrip
        ? leg.client_trip_started_at !== null && leg.client_arrived_at === null
        : LIVE_TECHNICIAN_STAGES.has(leg.stage);
      if (!moving) return json({ available: false, reason: "not_travelling" });

      const fromLat = clientTrip ? leg.client_latitude : leg.latitude;
      const fromLng = clientTrip ? leg.client_longitude : leg.longitude;
      if (!validCoordinate(fromLat, fromLng)) {
        return json({ available: false, reason: "no_position" });
      }

      const destination = await resolveLegDestination(db, job);
      if (destination.latitude === null || destination.longitude === null) {
        return json({ available: false, reason: "no_destination" });
      }

      return await routeBetween(
        fromLat,
        fromLng!,
        destination.latitude,
        destination.longitude,
        destination.label,
      );
    }

    // ----------------------------------------- from the caller's position
    const originLat = body.origin_latitude;
    const originLng = body.origin_longitude;
    if (!validCoordinate(originLat, originLng)) {
      return fail("A valid origin is required", 422);
    }

    let destLat: number | null = null;
    let destLng: number | null = null;
    let label: string;

    if (uid === job.assigned_technician_id) {
      // The technician driving to the client - on a home visit, or on either
      // leg of a pickup job.
      if (job.status !== "confirmed" && job.status !== "in_progress") {
        return fail(`This job is ${job.status}`, 409);
      }

      if (job.service_path === "pickup") {
        const { data: tracking } = await db
          .from("job_tracking")
          .select("stage")
          .eq("job_id", jobId)
          .maybeSingle<{ stage: string }>();

        const stage = tracking?.stage ?? null;

        if (stage === "delivered") {
          return fail("This job is finished", 409);
        }

        // After the repair, whether there is a trip at all is the CLIENT's
        // call, not this technician's. No row means delivery, the default.
        if (stage === "in_repair" || stage === "ready_for_collection") {
          const { data: preference } = await db
            .from("job_return_preferences")
            .select("method")
            .eq("job_id", jobId)
            .maybeSingle<{ method: string }>();

          if (preference?.method === "client_pickup") {
            return fail(
              "The client is collecting this one from your shop",
              409,
            );
          }
        }
      } else if (job.service_path !== "home_service") {
        return fail("Routing is for home-service and pickup jobs", 409);
      }

      destLat = job.latitude;
      destLng = job.longitude;
      label = "Client address";
    } else if (uid === job.client_id) {
      // The client going to collect a repaired unit.
      const { data: tracking } = await db
        .from("job_tracking")
        .select("stage, technician_id")
        .eq("job_id", jobId)
        .maybeSingle<{ stage: string; technician_id: string }>();

      // Two ways in. The unit is waiting at the shop, or - since
      // 20260922000005 - the client has said they will collect it, in which
      // case the route opens straight away so they can see where the shop
      // is and plan the trip before it is ready.
      const { data: preference } = await db
        .from("job_return_preferences")
        .select("method")
        .eq("job_id", jobId)
        .maybeSingle<{ method: string }>();

      const collecting = preference?.method === "client_pickup" &&
        (job.status === "confirmed" || job.status === "in_progress") &&
        tracking?.stage !== "delivered";

      if (tracking?.stage !== "ready_for_collection" && !collecting) {
        return fail("The workshop route opens once it is ready to collect", 409);
      }

      // The tracking row names the technician once they have started; before
      // that the job's own assignment does.
      const technicianId = tracking?.technician_id ?? job.assigned_technician_id;
      if (!technicianId) {
        return json({ available: false, reason: "no_destination" });
      }

      const { data: tech } = await db
        .from("technicians")
        .select("shop_latitude, shop_longitude, base_latitude, base_longitude")
        .eq("id", technicianId)
        .maybeSingle<{
          shop_latitude: number | null;
          shop_longitude: number | null;
          base_latitude: number | null;
          base_longitude: number | null;
        }>();

      // Shop, then base, then nothing - never the live position. See header.
      destLat = tech?.shop_latitude ?? tech?.base_latitude ?? null;
      destLng = tech?.shop_longitude ?? tech?.base_longitude ?? null;
      label = "Workshop";
    } else {
      return fail("This job belongs to someone else", 403);
    }

    if (destLat === null || destLng === null) {
      return json({ available: false, reason: "no_destination" });
    }

    return await routeBetween(originLat, originLng!, destLat, destLng, label);
  } catch (error) {
    console.warn("route failed", (error as Error).message);
    return json({ available: false, reason: "provider_unavailable" });
  }
});

/**
 * The road route from one point to another, as the app draws it. Shared by
 * both modes; every failure is an `available: false` with a reason.
 */
async function routeBetween(
  originLat: number,
  originLng: number,
  destLat: number,
  destLng: number,
  label: string,
): Promise<Response> {
  try {
    const straightKm = haversineKm(originLat, originLng, destLat, destLng);
    if (straightKm > MAX_ROUTE_KM) {
      return json({ available: false, reason: "too_far" });
    }

    const key = Deno.env.get("TOMTOM_API_KEY");
    if (!key) {
      console.warn("TOMTOM_API_KEY is not set; in-app routing unavailable");
      return json({ available: false, reason: "not_configured" });
    }

    const url = `https://api.tomtom.com/routing/1/calculateRoute/` +
      `${originLat},${originLng}:${destLat},${destLng}/json` +
      `?key=${key}&traffic=true&travelMode=${TRAVEL_MODE}` +
      `&routeRepresentation=polyline`;

    const response = await fetch(url, {
      signal: AbortSignal.timeout(ROUTE_TIMEOUT_MS),
    });

    if (!response.ok) {
      // TomTom answers 400 when the two points are not joined by the road
      // network - an origin in the sea, a pin on an island. That is a real
      // answer about the world, not an outage, so it gets its own reason.
      const text = await response.text();
      console.warn(`TomTom route returned ${response.status}: ${text.slice(0, 200)}`);
      return json({
        available: false,
        reason: response.status === 400 ? "no_route" : "provider_unavailable",
      });
    }

    const payload = await response.json() as {
      routes?: Array<{
        summary?: {
          lengthInMeters?: number;
          travelTimeInSeconds?: number;
          trafficDelayInSeconds?: number;
        };
        legs?: Array<{ points?: Array<{ latitude: number; longitude: number }> }>;
      }>;
    };

    const route = payload.routes?.[0];
    const points = (route?.legs ?? []).flatMap((leg) => leg.points ?? []);

    if (!route || points.length < 2) {
      return json({ available: false, reason: "no_route" });
    }

    // Even thinning, always keeping the final point so the line still meets
    // the destination pin.
    const stride = Math.ceil(points.length / MAX_POINTS);
    const thinned = points.filter((_, i) =>
      i % stride === 0 || i === points.length - 1
    );

    return json({
      available: true,
      // [lat, lng] pairs rather than objects: roughly half the bytes over a
      // mobile connection for the same geometry.
      points: thinned.map((p) => [p.latitude, p.longitude]),
      distance_m: route.summary?.lengthInMeters ?? null,
      travel_s: route.summary?.travelTimeInSeconds ?? null,
      traffic_delay_s: route.summary?.trafficDelayInSeconds ?? 0,
      destination: { latitude: destLat, longitude: destLng, label },
    });
  } catch (error) {
    console.warn("route failed", (error as Error).message);
    return json({ available: false, reason: "provider_unavailable" });
  }
}
