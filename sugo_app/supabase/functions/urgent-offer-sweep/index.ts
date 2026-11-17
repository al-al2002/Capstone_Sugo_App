/**
 * urgent-offer-sweep - passes an unanswered URGENT request to the next
 * technician (2026-11-17).
 *
 * POST /functions/v1/urgent-offer-sweep
 * header: x-cron-secret: <CRON_SECRET>
 *
 * Called by pg_cron every 30 seconds
 * (`20261117000002_urgent_offer_sweep_cron.sql`), never by the app.
 *
 * ## The rule (the user's)
 *
 * "When the task is urgent I want hard notify the technician, then countdown
 * 5 mins; if the technician does not accept the urgent task, the system sends
 * the request to another technician."
 *
 * So, for every request that is still `offered` five minutes after it was
 * sent (`job_matches.offered_at`) on a job posted as Urgent:
 *
 * 1. **It is passed on.** The row becomes `declined` - guarded on still being
 *    `offered`, so a technician who accepts at 4:59 wins the race and nothing
 *    happens. A timeout counts as a decline: the technician did not take it.
 * 2. **The next technician gets it** - the next on the client's shortlist by
 *   rank, skipping anyone on vacation or already on a job (they could not
 *   accept within five minutes anyway). When the shortlist is used up, the
 *   engine is re-run without everyone already asked, and its new top pick
 *   gets it.
 * 3. **Everyone is told.** The new technician gets the same hard
 *   notification and a fresh five minutes; the client hears it moved on; the
 *   technician who let it lapse hears that it went to someone else.
 *
 * ## Why only urgent jobs
 *
 * Since 2026-09-16 a declined request goes back to the CLIENT to choose again
 * (the `shortlisted` state), so no technician is handed a job nobody picked.
 * The user asked for the opposite on urgent jobs, where five minutes of a
 * client deciding is five minutes lost - so this sweep touches urgent jobs
 * only, and a flexible job keeps the client-chooses rule.
 *
 * ## Auth
 *
 * The same as `tracking-eta-sweep`: the cron carries `CRON_SECRET`, which
 * grants only this, rather than a service-role key written into `cron.job`.
 */
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { deviceNoun, firstNameOf, notifyUser } from "../_shared/notify.ts";
import {
  deliveryFee,
  shopDistanceKm,
  type ShopLocation,
} from "../_shared/delivery_fee.ts";
import { URGENT_RESPONSE_SECONDS, urgentOfferPush } from "../_shared/urgent.ts";
import { runMatching } from "../match-technician/scoring/engine.ts";
import type { JobRow } from "../match-technician/scoring/types.ts";

/** Enough for a burst; anything left is picked up 30 seconds later. */
const MAX_PER_RUN = 20;

interface ExpiredOffer {
  id: string;
  job_id: string;
  technician_id: string;
  rank: number;
  offered_at: string;
  jobs: JobRow;
}

interface Candidate {
  id: string;
  technician_id: string;
  rank: number;
  score_breakdown: Record<string, unknown> | null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const expected = Deno.env.get("CRON_SECRET");
    if (!expected) {
      console.warn("CRON_SECRET is not set; urgent sweep is disabled");
      return fail("Sweep is not configured", 503);
    }
    if (req.headers.get("x-cron-secret") !== expected) {
      return fail("Not authorised", 401);
    }

    const db = serviceClient();
    const cutoff = new Date(Date.now() - URGENT_RESPONSE_SECONDS * 1000)
      .toISOString();

    const { data, error } = await db
      .from("job_matches")
      .select("id, job_id, technician_id, rank, offered_at, jobs!inner(*)")
      .eq("status", "offered")
      .lt("offered_at", cutoff)
      .eq("jobs.urgency", "need_today")
      .order("offered_at", { ascending: true })
      .limit(MAX_PER_RUN)
      .returns<ExpiredOffer[]>();

    if (error) return fail("Could not read offers", 500, error.message);

    const results: Record<string, unknown>[] = [];
    for (const offer of data ?? []) {
      results.push(await passOn(db, offer));
    }

    return json({ checked: (data ?? []).length, results });
  } catch (err) {
    return fail("Urgent sweep failed", 500, (err as Error).message);
  }
});

/** Steps 1-3 for one lapsed request. */
async function passOn(
  db: SupabaseClient,
  offer: ExpiredOffer,
): Promise<Record<string, unknown>> {
  const job = offer.jobs;

  // 1. Pass it on - only if it is still waiting. An accept that landed first
  //    leaves this update matching nothing.
  const { data: lapsed } = await db
    .from("job_matches")
    .update({ status: "declined" })
    .eq("id", offer.id)
    .eq("status", "offered")
    .select("id");
  if (!lapsed || lapsed.length === 0) {
    return { match_id: offer.id, skipped: "answered meanwhile" };
  }

  const device = deviceNoun(job.device_type);
  const previous = await firstNameOf(db, offer.technician_id, "The technician");

  await notifyUser(db, offer.technician_id, {
    title: "Urgent request passed on",
    body: `You did not answer the urgent ${device} request within 5 minutes, ` +
      "so it went to another technician.",
    data: { type: "urgent_missed", job_id: job.id },
  });

  // 2. The next technician.
  const next = await nextCandidate(db, job);
  if (!next) {
    await notifyUser(db, job.client_id, {
      title: "No technician answered yet",
      body: `${previous} did not answer your urgent ${device} request and ` +
        "nobody else is free right now. Open SUGO to try again.",
      data: { type: "urgent_unanswered", job_id: job.id },
    });
    console.log(`job ${job.id}: urgent request lapsed, nobody left`);
    return { match_id: offer.id, passed_to: null };
  }

  // A shop delivery is priced to the shop it goes to: the new technician's.
  const breakdown = await repriceForShop(db, job, next);

  const { data: promoted } = await db
    .from("job_matches")
    .update(breakdown ? { status: "offered", score_breakdown: breakdown } : {
      status: "offered",
    })
    .eq("id", next.id)
    .eq("status", "shortlisted")
    .select("id");
  if (!promoted || promoted.length === 0) {
    return { match_id: offer.id, skipped: "next option changed meanwhile" };
  }

  // 3. Tell everyone.
  const client = await firstNameOf(db, job.client_id, "A client");
  await notifyUser(
    db,
    next.technician_id,
    urgentOfferPush(client, device, job.id, next.id, new Date(), true),
  );
  const nextName = await firstNameOf(db, next.technician_id, "another technician");
  await notifyUser(db, job.client_id, {
    title: "Your urgent request moved on",
    body: `${previous} did not answer within 5 minutes, so we sent it to ` +
      `${nextName}.`,
    data: { type: "urgent_forwarded", job_id: job.id },
  });

  console.log(
    `job ${job.id}: urgent request passed from ${offer.technician_id} ` +
      `to ${next.technician_id} (rank ${next.rank})`,
  );
  return { match_id: offer.id, passed_to: next.id };
}

/**
 * The next technician to ask: the client's shortlist in rank order, skipping
 * anyone away or already on a job; failing that, a fresh run of the engine
 * without everyone already asked, and its top pick.
 */
async function nextCandidate(
  db: SupabaseClient,
  job: JobRow,
): Promise<Candidate | null> {
  const { data: shortlist } = await db
    .from("job_matches")
    .select("id, technician_id, rank, score_breakdown")
    .eq("job_id", job.id)
    .eq("status", "shortlisted")
    .order("rank", { ascending: true })
    .returns<Candidate[]>();

  for (const option of shortlist ?? []) {
    if (await canTakeItNow(db, option.technician_id, job.id)) return option;
  }

  // Shortlist used up: ask the engine again, without anyone already asked.
  const { data: asked } = await db
    .from("job_matches")
    .select("technician_id")
    .eq("job_id", job.id)
    .returns<{ technician_id: string }[]>();
  const exclude = [...new Set((asked ?? []).map((r) => r.technician_id))];

  await db.from("jobs").update({ status: "pending" }).eq("id", job.id);
  const result = await runMatching(db, job, exclude);

  const fresh = (result.matches as Candidate[])
    .slice()
    .sort((a, b) => a.rank - b.rank);
  for (const option of fresh) {
    if (await canTakeItNow(db, option.technician_id, job.id)) return option;
  }
  return null;
}

/** Not on vacation and not on another job - able to accept right away. */
async function canTakeItNow(
  db: SupabaseClient,
  technicianId: string,
  jobId: string,
): Promise<boolean> {
  const { data: awayUntil } = await db.rpc("technician_away_until", {
    p_technician_id: technicianId,
  });
  if (awayUntil) return false;

  const { data: busy } = await db
    .from("jobs")
    .select("id")
    .eq("assigned_technician_id", technicianId)
    .in("status", ["confirmed", "in_progress"])
    .neq("id", jobId)
    .limit(1);
  return !busy || busy.length === 0;
}

/**
 * A shop repair's fee and distance belong to the chosen technician's shop,
 * so they are redone for the new one - the same rule `job-response` applies
 * when the client chooses. Returns the snapshot to write, or null when the
 * job is not a shop repair.
 */
async function repriceForShop(
  db: SupabaseClient,
  job: JobRow,
  next: Candidate,
): Promise<Record<string, unknown> | null> {
  if (job.service_path !== "pickup") return null;

  const { data: shop } = await db
    .from("technicians")
    .select("shop_latitude, shop_longitude, base_latitude, base_longitude")
    .eq("id", next.technician_id)
    .maybeSingle<ShopLocation>();

  const option = job.delivery_option === "self" ? "self" : "delivery";
  const distanceKm = shop ? shopDistanceKm(job.latitude, job.longitude, shop) : null;
  const fee = option === "self"
    ? 0
    : distanceKm === null
    ? null
    : deliveryFee(distanceKm);

  await db
    .from("jobs")
    .update({ delivery_option: option, distance_km: distanceKm, delivery_fee: fee })
    .eq("id", job.id);

  const breakdown = next.score_breakdown;
  if (!breakdown || typeof breakdown.job !== "object" || !breakdown.job) {
    return null;
  }
  return {
    ...breakdown,
    job: {
      ...(breakdown.job as Record<string, unknown>),
      delivery_option: option,
      distance_km: distanceKm,
      delivery_fee: fee,
    },
  };
}
