/**
 * Where the current tracking leg is heading.
 *
 * Two functions need this and must never disagree: `job-weather` reports the
 * conditions there, and `tracking-eta` measures the distance to it. If one
 * resolved the workshop and the other the client's address, the chip would
 * describe weather at a place the ETA was not counting down to.
 *
 * Extracted here rather than duplicated for that reason alone.
 */
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

/** Stages where the unit is travelling back to the client. */
export const OUTBOUND_STAGES = new Set(["out_for_delivery", "delivered"]);

/**
 * The technician driving TO the client: to collect the unit on a workshop job,
 * or - since 2026-09-29 - to do the repair itself on a home-service job.
 *
 * This stage used to fall through to the workshop with the rest of the inbound
 * leg, so a client whose technician was on the way to them was measured an ETA,
 * and shown the weather, for a shop across town. `job-route` already routed
 * this leg to the client's address; now all three agree.
 */
export const HEADING_TO_CLIENT_STAGE = "heading_to_pickup";

export interface LegDestination {
  latitude: number | null;
  longitude: number | null;
  /** Reads naturally after "at": "your address", "the drop-off", "the workshop". */
  label: string;
  outbound: boolean;
  /** The tracking row's current stage, or null when there is no leg at all. */
  stage: string | null;
}

export interface LegJob {
  id: string;
  client_id: string;
  assigned_technician_id: string | null;
  latitude: number | null;
  longitude: number | null;
}

/**
 * Resolves the destination for a job's current leg.
 *
 * Returns `stage: null` when the job has no tracking row - there is no leg, so
 * there is nothing to head towards.
 */
export async function resolveLegDestination(
  db: SupabaseClient,
  job: LegJob,
): Promise<LegDestination> {
  const { data: tracking } = await db
    .from("job_tracking")
    .select("stage")
    .eq("job_id", job.id)
    .maybeSingle<{ stage: string }>();

  if (!tracking) {
    return {
      latitude: null,
      longitude: null,
      label: "the destination",
      outbound: false,
      stage: null,
    };
  }

  const outbound = OUTBOUND_STAGES.has(tracking.stage);

  if (outbound) {
    return {
      latitude: job.latitude,
      longitude: job.longitude,
      label: "the drop-off",
      outbound: true,
      stage: tracking.stage,
    };
  }

  // Only the client reads this label (the weather chip), and to them it is
  // their own address. `outbound` stays false: nothing is coming BACK yet.
  if (tracking.stage === HEADING_TO_CLIENT_STAGE) {
    return {
      latitude: job.latitude,
      longitude: job.longitude,
      label: "your address",
      outbound: false,
      stage: tracking.stage,
    };
  }

  let latitude: number | null = null;
  let longitude: number | null = null;

  if (job.assigned_technician_id) {
    const { data: tech } = await db
      .from("technicians")
      .select(
        "shop_latitude, shop_longitude, base_latitude, base_longitude, " +
          "latitude, longitude",
      )
      .eq("id", job.assigned_technician_id)
      .maybeSingle<{
        shop_latitude: number | null;
        shop_longitude: number | null;
        base_latitude: number | null;
        base_longitude: number | null;
        latitude: number | null;
        longitude: number | null;
      }>();

    // Shop first, then the registered base, then whatever live position is on
    // the row - the same order the tracking map falls back through.
    latitude = tech?.shop_latitude ?? tech?.base_latitude ?? tech?.latitude ??
      null;
    longitude = tech?.shop_longitude ?? tech?.base_longitude ??
      tech?.longitude ?? null;
  }

  return {
    latitude,
    longitude,
    label: "the workshop",
    outbound: false,
    stage: tracking.stage,
  };
}
