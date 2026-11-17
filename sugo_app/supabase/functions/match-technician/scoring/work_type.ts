/**
 * The work-type gate (2026-11-17, migration 20261117000007).
 *
 * A technician says at registration which work they take: Home Service (they
 * go to the client), Shop Repair (the unit comes to their shop), or both. A
 * job is only offered to technicians who take its kind of work:
 *
 *   service_path 'home_service' -> offers_home_service
 *   service_path 'pickup'       -> offers_shop_repair
 *
 * A hard gate in Stage 1, beside the identity gates, not a weight: a client
 * who chose Shop Repair and is offered someone with no shop has not been
 * given a worse match, they have been given a wrong one.
 *
 * `match_technicians_for_job` (the wider list, ranks 4+) applies the same
 * rule in SQL, so the two lists can never disagree.
 *
 * Kept free of Supabase so it can be tested with Node alone.
 */

/** The two flags as `matching_candidates` returns them. */
export interface WorkTypeFlags {
  /** Undefined only from a view older than the migration: counts as yes. */
  offers_home_service?: boolean | null;
  offers_shop_repair?: boolean | null;
}

/**
 * Whether a technician takes the work a job needs.
 *
 * A missing flag counts as yes - only an explicit `false` excludes - so a
 * function deployed before the migration keeps matching everyone, as it did.
 * A job with no path, or a community question, has no work type to gate on.
 */
export function takesWorkFor(
  technician: WorkTypeFlags,
  servicePath: string | null | undefined,
): boolean {
  switch (servicePath) {
    case "home_service":
      return technician.offers_home_service !== false;
    case "pickup":
      return technician.offers_shop_repair !== false;
    default:
      return true;
  }
}

/** The client-facing words for a path, for the "nobody takes this" message. */
export function workTypeLabel(servicePath: string | null | undefined): string {
  return servicePath === "pickup" ? "Shop Repair" : "Home Service";
}
