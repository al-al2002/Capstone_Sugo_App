/**
 * Technician confirmation, the decline cascade, and the feedback loop.
 *
 * ```
 * POST /functions/v1/job-response
 * { "match_id": "uuid", "action": "accept" | "reroute" | "decline" }
 * { "job_id": "uuid", "action": "update_job", "job": { ...edited fields } }
 * { "job_id": "uuid", "action": "complete",
 *   "diagnosis_correct": true, "rerouted_mid_job": false, "final_rating": 4.5 }
 * ```
 *
 * ## Why this is server-side at all
 *
 * The RB-CARS migration gives `job_matches` and `job_outcomes` select policies
 * only. There is deliberately no insert or update policy on either, so no
 * client can write its own scores, mark itself accepted, or forge an outcome
 * that would feed back into future rankings. Every write here therefore runs on
 * the service role, and every one is gated on an explicit ownership check
 * against the JWT the caller sent.
 *
 * ## Who does what
 *
 * `select` is the **client** choosing one of the Top 3. It narrows the offer to
 * that technician and retires the other two, so only the chosen technician is
 * asked. Everything else - `accept`, `reroute`, `decline` - is the
 * **technician** answering. Those three never belong on a client screen.
 *
 * ## The decline cascade (Step 7)
 *
 * Rank 1 declines -> mark that row declined, rank 2 is now the live offer.
 * Rank 2 declines -> rank 3.
 * Rank 3 declines -> nothing is left, so Stage 2 is re-run against the pool
 * with all three decliners excluded. Conditions have moved on by then - traffic,
 * weather and workloads are all re-read - so the new Top 3 is a fresh answer,
 * not a replay of the old one.
 */
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, readJson, serviceClient } from "../_shared/supabase.ts";
import { deviceNoun, firstNameOf, notifyUser } from "../_shared/notify.ts";
import { formatAwayUntil } from "../match-technician/scoring/acceptance.ts";
import { runMatching } from "../match-technician/scoring/engine.ts";
import type { JobRow } from "../match-technician/scoring/types.ts";

type Action =
  | "accept"
  | "reroute"
  | "decline"
  | "complete"
  | "select"
  // Mid-job: an on-site repair the technician cannot finish at the client's
  // home. See handleNeedsShop.
  | "needs_shop"
  // The client removing a job nobody has taken. See handleDeleteJob.
  | "delete_job"
  // The client editing a job nobody has taken. See handleUpdateJob.
  | "update_job";

interface ResponseRequest {
  match_id?: string;
  job_id?: string;
  action?: Action;
  /** `update_job` only: the edited columns. Anything not whitelisted is ignored. */
  job?: Record<string, unknown>;
  /** `complete` only. */
  diagnosis_correct?: boolean;
  rerouted_mid_job?: boolean;
  final_rating?: number;
}

interface MatchRow {
  id: string;
  job_id: string;
  technician_id: string;
  rank: number;
  status: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const body = await readJson<ResponseRequest>(req);
    const action = body.action;

    if (!action) return fail("action is required", 422);

    const db = serviceClient();

    if (action === "complete") {
      return await handleComplete(db, uid, body);
    }

    if (action === "select") {
      return await handleClientSelect(db, uid, body);
    }

    if (action === "needs_shop") {
      return await handleNeedsShop(db, uid, body);
    }

    if (action === "delete_job") {
      return await handleDeleteJob(db, uid, body);
    }

    if (action === "update_job") {
      return await handleUpdateJob(db, uid, body);
    }

    // ------------------------------------------- accept / reroute / decline
    const matchId = body.match_id;
    if (!matchId) return fail("match_id is required", 422);

    const { data: match, error: matchError } = await db
      .from("job_matches")
      .select("id, job_id, technician_id, rank, status")
      .eq("id", matchId)
      .maybeSingle<MatchRow>();

    if (matchError) {
      return fail("Could not load the offer", 500, matchError.message);
    }
    if (!match) return fail("Offer not found", 404);

    // Only the technician the offer was made to may answer it.
    if (match.technician_id !== uid) {
      return fail("This offer was made to another technician", 403);
    }
    if (match.status !== "offered") {
      return fail(`This offer was already ${match.status}`, 409);
    }

    const { data: job, error: jobError } = await db
      .from("jobs")
      .select("*")
      .eq("id", match.job_id)
      .maybeSingle<JobRow>();

    if (jobError) return fail("Could not load the job", 500, jobError.message);
    if (!job) return fail("Job not found", 404);

    if (job.status === "confirmed" || job.status === "in_progress") {
      return fail("This job has already been confirmed", 409);
    }
    if (job.status === "cancelled" || job.status === "completed") {
      return fail(`This job is ${job.status}`, 409);
    }

    if (action === "accept" || action === "reroute") {
      return await handleAccept(db, match, job, action);
    }
    return await handleDecline(db, match, job);
  } catch (error) {
    return fail("Could not record the response", 500, (error as Error).message);
  }
});

// ---------------------------------------------------------------------------

/**
 * The client picks one of the Top 3.
 *
 * RB-CARS offers a job to three technicians at once so the client can compare
 * them. Leaving all three live after a choice would mean three technicians
 * racing to accept a job that has already been given away. So selecting one
 * retires the other two.
 *
 * The chosen row is PROMOTED from `shortlisted` to `offered`, not to
 * `accepted`: the client has requested this technician, but the technician has
 * not yet agreed. Only they can do that, from their own dashboard.
 *
 * This promotion is the only way a row ever becomes `offered`, and therefore
 * the only way a job reaches a technician's dashboard at all. That is the whole
 * point: the engine ranking you is not the same as a client booking you.
 */
async function handleClientSelect(
  db: SupabaseClient,
  uid: string,
  body: ResponseRequest,
): Promise<Response> {
  const matchId = body.match_id;
  if (!matchId) return fail("match_id is required", 422);

  const { data: match, error: matchError } = await db
    .from("job_matches")
    .select("id, job_id, technician_id, rank, status")
    .eq("id", matchId)
    .maybeSingle<MatchRow>();

  if (matchError) {
    return fail("Could not load the offer", 500, matchError.message);
  }
  if (!match) return fail("Offer not found", 404);

  const { data: job, error: jobError } = await db
    .from("jobs")
    .select("*")
    .eq("id", match.job_id)
    .maybeSingle<JobRow>();

  if (jobError) return fail("Could not load the job", 500, jobError.message);
  if (!job) return fail("Job not found", 404);

  // Only the client who posted the job may choose. A technician cannot select
  // themselves into a booking.
  if (job.client_id !== uid) {
    return fail("This job belongs to someone else", 403);
  }
  if (job.status === "confirmed" || job.status === "in_progress") {
    return fail("This job has already been confirmed", 409);
  }
  // The client may only choose from their shortlist. An `offered` row has
  // already been chosen once and is sitting on a technician's dashboard; an
  // `accepted` or `declined` one is finished.
  if (match.status !== "shortlisted") {
    return fail(
      match.status === "offered"
        ? "You have already chosen this technician"
        : `That option is no longer ${match.status === "declined" ? "available" : "open"}`,
      409,
    );
  }

  // A technician on vacation is shown but cannot be booked.
  //
  // Checked live, not read from the card: the card is a snapshot taken when
  // matching ran, and a vacation may have started since. Checked here because
  // this promotion is the only way a job ever reaches a technician - so a
  // client on an old build, or calling this function directly, meets the same
  // rule as one tapping the disabled button. Placed before every write, so a
  // refusal leaves the job exactly as it was.
  const { data: awayUntil, error: awayError } = await db.rpc(
    "technician_away_until",
    { p_technician_id: match.technician_id },
  );

  if (awayError) {
    return fail("Could not check the technician's schedule", 500, awayError.message);
  }
  if (awayUntil) {
    return fail(
      `This technician is on vacation until ${formatAwayUntil(awayUntil as string)} ` +
        "and cannot be booked. Choose another technician.",
      409,
    );
  }

  // Retire any request already outstanding on this job - the client has changed
  // their mind before the first technician answered. Done BEFORE the promotion
  // so a failure here cannot leave two technicians holding a live offer for the
  // same job, which is the worse of the two half-finished states.
  //
  // Note this clears `offered` rows, NOT the rest of the shortlist. The other
  // two stay `shortlisted` on purpose: they are invisible to technicians and
  // cannot be accepted, so they are not a race, and keeping them means a
  // decline sends the client back to their own shortlist instead of forcing a
  // full re-match. The old code retired them here because under the previous
  // three-state model leaving them live really would have been a race.
  const { error: retireError } = await db
    .from("job_matches")
    .update({ status: "declined" })
    .eq("job_id", job.id)
    .eq("status", "offered")
    .neq("id", match.id);

  if (retireError) {
    return fail("Could not update the other options", 500, retireError.message);
  }

  // Promote the chosen one. This is what puts the job on their dashboard.
  const { error: promoteError } = await db
    .from("job_matches")
    .update({ status: "offered" })
    .eq("id", match.id);

  if (promoteError) {
    return fail("Could not send your request", 500, promoteError.message);
  }

  console.log(
    `job ${job.id}: client selected technician ${match.technician_id} (rank ${match.rank})`,
  );

  // The technician has been booked. Pushed rather than left for them to find:
  // a request that sits unseen on a closed app is the slow technician the
  // client then cancels. Awaited, but never fatal - see notifyUser.
  const client = await firstNameOf(db, job.client_id, "A client");
  await notifyUser(db, match.technician_id, {
    title: "New job request",
    body: `${client} booked you for a ${deviceNoun(job.device_type)} repair. ` +
      "Open SUGO to accept it.",
    data: { type: "booked", job_id: job.id },
  });

  return json({
    job_id: job.id,
    match_id: match.id,
    technician_id: match.technician_id,
    status: "awaiting_technician",
  });
}

/**
 * Accept (fix it on site) or reroute (it needs the shop).
 *
 * A reroute is still an acceptance - the technician is taking the job - but it
 * changes the service path to `pickup`, which is what the client sees on the
 * booking. Recording it here is what later lets `job_outcomes.rerouted_mid_job`
 * be filled in honestly, and that in turn discounts the technician's diagnosis
 * accuracy in `scoring/accuracy.ts`. Getting the path wrong has a cost.
 */
async function handleAccept(
  db: SupabaseClient,
  match: MatchRow,
  job: JobRow,
  action: "accept" | "reroute",
): Promise<Response> {
  const rerouted = action === "reroute";

  const { error: matchError } = await db
    .from("job_matches")
    .update({ status: "accepted" })
    .eq("id", match.id);

  if (matchError) {
    return fail("Could not accept the offer", 500, matchError.message);
  }

  const jobUpdate: Record<string, unknown> = {
    status: "confirmed",
    assigned_technician_id: match.technician_id,
  };
  if (rerouted) jobUpdate.service_path = "pickup";

  const { error: jobError } = await db
    .from("jobs")
    .update(jobUpdate)
    .eq("id", job.id);

  if (jobError) {
    return fail("Could not confirm the job", 500, jobError.message);
  }

  // Retire everything else still open on this job: the job is taken.
  //
  // `shortlisted` is included, not just `offered`. The client keeps their
  // unchosen shortlist while they are still deciding, so once someone accepts
  // those rows have to be closed too - otherwise a confirmed job would still
  // show the client two technicians they could apparently still pick.
  await db
    .from("job_matches")
    .update({ status: "declined" })
    .eq("job_id", job.id)
    .in("status", ["shortlisted", "offered"])
    .neq("id", match.id);

  // Workload is what Stage 2 reads to spread jobs around, so it has to move
  // the moment a job is taken, not when it is completed.
  await adjustWorkload(db, match.technician_id, 1);

  // A reroute means the unit travels: to the shop now, back to the client
  // after the repair. Opening the tracking row here rather than making the
  // technician start it by hand means the client's map exists from the moment
  // they are told their appliance is being collected.
  if (rerouted) {
    const { error: trackingError } = await db
      .from("job_tracking")
      .upsert({
        job_id: job.id,
        technician_id: match.technician_id,
        stage: "heading_to_pickup",
      }, { onConflict: "job_id" });

    if (trackingError) {
      // Not fatal. The booking is confirmed either way, and the technician can
      // start tracking from their own screen if this failed.
      console.warn("could not open tracking:", trackingError.message);
    }
  }

  // TODO(tracking): hand off to the tracking / evidence-timeline feature here.
  // That flow owns `in_progress`, the arrival timestamps and the photo
  // evidence trail. It is a separate capstone module; this function's
  // responsibility ends at `confirmed`.

  return json({
    job_id: job.id,
    match_id: match.id,
    status: "confirmed",
    service_path: rerouted ? "pickup" : job.service_path,
    rerouted,
    next: "tracking",
  });
}

/**
 * Decline, then cascade.
 *
 * Marks this offer declined and looks for the next-ranked live offer. If none
 * remains, Stage 2 is re-run against the remaining pool.
 */
async function handleDecline(
  db: SupabaseClient,
  match: MatchRow,
  job: JobRow,
): Promise<Response> {
  const { error } = await db
    .from("job_matches")
    .update({ status: "declined" })
    .eq("id", match.id);

  if (error) return fail("Could not decline the offer", 500, error.message);

  // What is left of the client's shortlist.
  //
  // These are deliberately NOT auto-promoted to `offered`. Handing the job
  // straight to rank 2 would put it on a technician's dashboard that no client
  // ever chose - which is precisely the bug the `shortlisted` state exists to
  // prevent, reintroduced one layer down. The choice goes back to the client,
  // who selects again from the shortlist they were already looking at.
  const { data: remaining } = await db
    .from("job_matches")
    .select("id, job_id, technician_id, rank, status")
    .eq("job_id", job.id)
    .eq("status", "shortlisted")
    .order("rank", { ascending: true })
    .returns<MatchRow[]>();

  const shortlist = remaining ?? [];

  if (shortlist.length > 0) {
    return json({
      job_id: job.id,
      declined_match_id: match.id,
      // No offer was created, so there is no next one to report.
      next_offer: null,
      rematched: false,
      // The client has someone else to pick, and the app should send them back
      // to the shortlist rather than showing "we are finding you someone".
      awaiting_client_reselect: true,
      shortlist_remaining: shortlist.length,
    });
  }

  // The shortlist is exhausted. Re-run the engine, excluding everyone who has
  // already been through it.
  const { data: previous } = await db
    .from("job_matches")
    .select("technician_id")
    .eq("job_id", job.id)
    .returns<{ technician_id: string }[]>();

  // Deduplicate into a typed set: the same technician can appear on more than
  // one offer if an earlier re-match already put them forward.
  const excluded = new Set<string>();
  for (const row of previous ?? []) {
    excluded.add(row.technician_id);
  }
  const exclude: string[] = [...excluded];

  console.log(
    `job ${job.id}: all offers declined, re-running with ${exclude.length} excluded`,
  );

  // Put the job back to `pending` so the engine's own `pending -> matched`
  // transition fires on the fresh set.
  await db.from("jobs").update({ status: "pending" }).eq("id", job.id);

  const result = await runMatching(db, job, exclude);

  return json({
    job_id: job.id,
    declined_match_id: match.id,
    next_offer: null,
    rematched: true,
    evaluated: result.evaluated,
    matches: result.matches,
    message: result.message,
  });
}

/**
 * Completion and the feedback loop (Step 8).
 *
 * Writes one `job_outcomes` row, then refreshes the technician's denormalised
 * counters. `diagnosis_correct` and `rerouted_mid_job` are the two signals
 * `scoring/accuracy.ts` reads back into Stage 1, so this is the point where the
 * system learns.
 *
 * `final_rating` is only accepted from the client who posted the job. A
 * technician cannot rate themselves.
 */
async function handleComplete(
  db: SupabaseClient,
  uid: string,
  body: ResponseRequest,
): Promise<Response> {
  const jobId = body.job_id;
  if (!jobId) return fail("job_id is required", 422);

  const { data: job, error: jobError } = await db
    .from("jobs")
    .select("*")
    .eq("id", jobId)
    .maybeSingle<JobRow>();

  if (jobError) return fail("Could not load the job", 500, jobError.message);
  if (!job) return fail("Job not found", 404);

  const isClient = job.client_id === uid;
  const isAssigned = job.assigned_technician_id === uid;

  if (!isClient && !isAssigned) {
    return fail("This job belongs to someone else", 403);
  }
  if (!job.assigned_technician_id) {
    return fail("This job has no assigned technician", 409);
  }

  const { data: existing } = await db
    .from("job_outcomes")
    .select("id")
    .eq("job_id", jobId)
    .maybeSingle<{ id: string }>();

  if (existing) {
    return fail("An outcome has already been recorded for this job", 409);
  }

  const rating = typeof body.final_rating === "number"
    ? Math.max(0, Math.min(5, body.final_rating))
    : null;

  const outcome = {
    job_id: jobId,
    technician_id: job.assigned_technician_id,
    diagnosis_correct: body.diagnosis_correct ?? null,
    rerouted_mid_job: body.rerouted_mid_job ?? false,
    // Only the paying client's rating counts.
    final_rating: isClient ? rating : null,
  };

  const { data: inserted, error: outcomeError } = await db
    .from("job_outcomes")
    .insert(outcome)
    .select()
    .single();

  if (outcomeError) {
    return fail("Could not record the outcome", 500, outcomeError.message);
  }

  await db.from("jobs").update({ status: "completed" }).eq("id", jobId);

  await adjustWorkload(db, job.assigned_technician_id, -1);
  await refreshTechnicianAggregates(db, job.assigned_technician_id);

  // Tell the OTHER side it is done, and invite the rating - the one moment a
  // rating is easy to give. Whoever closed the job is already looking at it.
  const closer = await firstNameOf(
    db,
    uid,
    isClient ? "Your client" : "Your technician",
  );
  await notifyUser(db, isClient ? job.assigned_technician_id : job.client_id, {
    title: "Job completed",
    body: isClient
      ? `${closer} closed the ${deviceNoun(job.device_type)} job. Tap to rate them.`
      : `${closer} finished your ${deviceNoun(job.device_type)} repair. ` +
        "Tap to rate them.",
    data: { type: "completed", job_id: jobId },
  });

  return json({ job_id: jobId, outcome: inserted, status: "completed" });
}

// ---------------------------------------------------------------------------

/** Nudges `current_workload`, never below zero. */
async function adjustWorkload(
  db: SupabaseClient,
  technicianId: string,
  delta: number,
) {
  const { data } = await db
    .from("technicians")
    .select("current_workload")
    .eq("id", technicianId)
    .maybeSingle<{ current_workload: number | null }>();

  const current = data?.current_workload ?? 0;
  const next = Math.max(0, current + delta);

  await db
    .from("technicians")
    .update({ current_workload: next })
    .eq("id", technicianId);
}

/**
 * Recomputes `rating` and `total_jobs` from `job_outcomes`, which is the
 * source of truth. Doing it here keeps a technician's card correct the moment
 * a job closes; `aggregate-outcomes` repeats the same work nightly across
 * everyone, so a missed call self-heals.
 */
async function refreshTechnicianAggregates(
  db: SupabaseClient,
  technicianId: string,
) {
  const { count } = await db
    .from("job_outcomes")
    .select("id", { count: "exact", head: true })
    .eq("technician_id", technicianId);

  await db
    .from("technicians")
    .update({ total_jobs: count ?? 0 })
    .eq("id", technicianId);

  // The rating is NOT computed here any more. It used to be - averaging
  // `final_rating` in TypeScript - while the `job_reviews` trigger computed the
  // same average in SQL. Float and numeric rounding could disagree by 0.01, and
  // whichever ran last won. Calling the one SQL definition removes the second
  // copy instead of promising to keep two in step.
  // See 20260917000002_single_source_rating.sql.
  const { error } = await db.rpc("recompute_technician_rating", {
    p_technician_id: technicianId,
  });
  if (error) console.warn("could not recompute rating:", error.message);
}

/**
 * Mid-job reroute: an on-site repair that turns out to need the workshop.
 *
 * ## Why this is not the same as accepting with "reroute"
 *
 * The offer screen used to carry a third button, "Needs shop", so a technician
 * had to predict from a photo and a symptom whether the unit would have to
 * travel. That is a guess made at the worst possible moment - before they have
 * seen the device. The honest answer usually only exists after they arrive,
 * open it up, and find the board needs a bench.
 *
 * So the decision moved to where the knowledge is. The offer is now just accept
 * or decline, and THIS is the escape hatch once they are on site.
 *
 * ## What it changes
 *
 * `service_path` becomes `pickup`, which is what the client's booking and the
 * tracking screen both key off, and a `job_tracking` row opens at
 * `heading_to_pickup` so the client's map exists from the moment they are told
 * their appliance is being collected.
 *
 * The job stays `confirmed`/`in_progress` - the booking did not change, only
 * where the repair happens.
 */
async function handleNeedsShop(
  db: SupabaseClient,
  uid: string,
  body: ResponseRequest,
): Promise<Response> {
  const jobId = body.job_id;
  if (!jobId) return fail("job_id is required", 422);

  const { data: job, error: jobError } = await db
    .from("jobs")
    .select("*")
    .eq("id", jobId)
    .maybeSingle<JobRow>();

  if (jobError) return fail("Could not load the job", 500, jobError.message);
  if (!job) return fail("Job not found", 404);

  // Only the technician actually on the job may say it needs the shop. Not the
  // client - this is a diagnosis, not a preference.
  if (job.assigned_technician_id !== uid) {
    return fail("This job is assigned to another technician", 403);
  }
  if (job.status !== "confirmed" && job.status !== "in_progress") {
    return fail(`This job is ${job.status}`, 409);
  }
  if (job.service_path === "pickup") {
    return fail("This job is already a shop pickup", 409);
  }

  const { error: updateError } = await db
    .from("jobs")
    .update({ service_path: "pickup" })
    .eq("id", jobId);

  if (updateError) {
    return fail("Could not switch to shop pickup", 500, updateError.message);
  }

  // Same upsert the accept path uses, so a job that somehow already has a
  // tracking row is not duplicated.
  const { error: trackingError } = await db
    .from("job_tracking")
    .upsert({
      job_id: jobId,
      technician_id: uid,
      stage: "heading_to_pickup",
    }, { onConflict: "job_id" });

  if (trackingError) {
    // Not fatal: the path is switched either way, and the technician can start
    // tracking from their own screen.
    console.warn("could not open tracking:", trackingError.message);
  }

  console.log(`job ${jobId}: rerouted to shop pickup mid-job by ${uid}`);

  return json({
    job_id: jobId,
    status: job.status,
    service_path: "pickup",
    rerouted: true,
  });
}

/**
 * The client removes a job nobody has taken.
 *
 * ## Why a real delete and not a `cancelled` status
 *
 * `jobs.status` has a `cancelled` value, and for a job with any history that is
 * the right answer - a technician who travelled, a repair that happened, an
 * outcome that feeds Stage 1 scoring. None of that exists here. An unbooked job
 * has no assigned technician, no outcome, no tracking and no chat. The only
 * rows pointing at it are `job_matches`, which record offers nobody accepted.
 *
 * Nothing downstream reads those: `scoring/accuracy.ts` learns from
 * `job_outcomes`, not from offers. So there is no history to preserve, and
 * leaving a cancelled row on the dashboard for ever is just clutter the client
 * asked to be rid of.
 *
 * ## Why the guards are strict
 *
 * A booked job must never be deletable. A technician may have driven across the
 * city for it, and the record of that belongs to them as much as to the client.
 * So this refuses the moment anyone has accepted:
 *
 *   - the caller must own the job
 *   - status must be `pending` or `matched` - never confirmed, in_progress,
 *     completed or cancelled
 *   - `assigned_technician_id` must be null
 *   - no match may have been accepted
 *
 * The last two are belt and braces over the status check: they are the facts
 * that actually mean "somebody took this", and a status can be moved by a bug.
 *
 * ## Known gap
 *
 * `photo_urls` point at storage objects that are NOT removed here, so deleting
 * a job with photos orphans them in the bucket. Storage cleanup is its own
 * concern - it needs the same treatment for cancelled and completed jobs - and
 * pretending to solve it with one unlink here would hide that.
 */
async function handleDeleteJob(
  db: SupabaseClient,
  uid: string,
  body: ResponseRequest,
): Promise<Response> {
  const jobId = body.job_id;
  if (!jobId) return fail("job_id is required", 422);

  const { data: job, error: jobError } = await db
    .from("jobs")
    .select("id, client_id, status, assigned_technician_id")
    .eq("id", jobId)
    .maybeSingle<{
      id: string;
      client_id: string;
      status: string;
      assigned_technician_id: string | null;
    }>();

  if (jobError) return fail("Could not load the job", 500, jobError.message);
  if (!job) return fail("Job not found", 404);

  if (job.client_id !== uid) {
    return fail("This job belongs to someone else", 403);
  }
  if (job.status !== "pending" && job.status !== "matched") {
    return fail(
      job.status === "cancelled"
        ? "This job was already cancelled"
        : "A technician has already taken this job, so it cannot be deleted",
      409,
    );
  }
  if (job.assigned_technician_id !== null) {
    return fail("This job already has a technician assigned", 409);
  }

  const { count: acceptedCount } = await db
    .from("job_matches")
    .select("id", { count: "exact", head: true })
    .eq("job_id", jobId)
    .eq("status", "accepted");

  if ((acceptedCount ?? 0) > 0) {
    return fail("A technician has already accepted this job", 409);
  }

  // `job_matches.job_id` has no ON DELETE CASCADE, so the offers have to go
  // first or the delete below fails on the foreign key.
  const { error: matchError } = await db
    .from("job_matches")
    .delete()
    .eq("job_id", jobId);

  if (matchError) {
    return fail("Could not clear the offers", 500, matchError.message);
  }

  const { error: deleteError } = await db.from("jobs").delete().eq("id", jobId);

  if (deleteError) {
    return fail("Could not delete the job", 500, deleteError.message);
  }

  console.log(`job ${jobId}: deleted by client ${uid} before any acceptance`);

  return json({ job_id: jobId, deleted: true });
}

/**
 * The columns a client may change when editing their post - the same ones the
 * posting flow writes, minus the two that are not theirs to set: `client_id`
 * (who owns it) and `status` (where it is in the lifecycle).
 *
 * A whitelist rather than "everything in the body", because this runs on the
 * service role: anything it writes bypasses RLS, so it must write only what a
 * client could have typed into the form.
 */
const EDITABLE_JOB_FIELDS = [
  "device_type",
  "device_detail",
  "brand",
  "problem_symptom",
  "has_physical_damage",
  "classification_confidence",
  "service_path",
  "urgency",
  "latitude",
  "longitude",
  "address_text",
  "budget_min",
  "budget_max",
  "preferred_schedule",
  "description",
  "photo_urls",
] as const;

/**
 * The client editing a job nobody has taken yet ("Edit post").
 *
 * ## Why here and not a direct update
 *
 * `jobs` is one of the four frozen RB-CARS tables and has no client update
 * policy, and an edit has to touch `job_matches` too, which has no client
 * write policy at all. So, like `delete_job`, it runs here on the service
 * role behind the same ownership and state checks.
 *
 * ## The rules - the same as deleting
 *
 * Only while the job is `pending` or `matched` and no technician has accepted.
 * After that the job is an agreement with a technician, and changing what was
 * agreed from one side is not an edit.
 *
 * ## What happens to the matches
 *
 * The open ones - the shortlist, and any request already sent - are cleared,
 * and the job goes back to `pending`. A Top 3 ranked for a laptop in Davao is
 * not a Top 3 for an aircon in Tagum, and a technician must not be able to
 * accept the old version of a job that has changed underneath them. The app
 * re-runs matching straight after, exactly as it does after posting.
 * `declined` and `accepted` rows are history and are kept.
 *
 * The matches are cleared BEFORE the job is changed, so there is no moment in
 * which a technician could accept an offer for details that no longer exist.
 */
async function handleUpdateJob(
  db: SupabaseClient,
  uid: string,
  body: ResponseRequest,
): Promise<Response> {
  const jobId = body.job_id;
  if (!jobId) return fail("job_id is required", 422);

  const changes = body.job;
  if (!changes || typeof changes !== "object") {
    return fail("job is required", 422);
  }

  const update: Record<string, unknown> = {};
  for (const key of EDITABLE_JOB_FIELDS) {
    if (key in changes) update[key] = changes[key];
  }
  if (Object.keys(update).length === 0) {
    return fail("Nothing to change", 422);
  }

  // The two answers the matcher cannot run without. The check constraints
  // catch bad enum values; these would otherwise be silently nulled.
  if ("problem_symptom" in update &&
      (typeof update.problem_symptom !== "string" || update.problem_symptom === "")) {
    return fail("Choose what is wrong with the device", 422);
  }
  if (("latitude" in update && typeof update.latitude !== "number") ||
      ("longitude" in update && typeof update.longitude !== "number")) {
    return fail("Set the location on the map", 422);
  }

  const { data: job, error: jobError } = await db
    .from("jobs")
    .select("id, client_id, status, assigned_technician_id")
    .eq("id", jobId)
    .maybeSingle<{
      id: string;
      client_id: string;
      status: string;
      assigned_technician_id: string | null;
    }>();

  if (jobError) return fail("Could not load the job", 500, jobError.message);
  if (!job) return fail("Job not found", 404);

  if (job.client_id !== uid) {
    return fail("This job belongs to someone else", 403);
  }
  if (job.status !== "pending" && job.status !== "matched") {
    return fail(
      job.status === "cancelled"
        ? "This job was cancelled, so it cannot be edited"
        : "A technician has already taken this job, so it cannot be edited",
      409,
    );
  }
  if (job.assigned_technician_id !== null) {
    return fail("This job already has a technician assigned", 409);
  }

  const { count: acceptedCount } = await db
    .from("job_matches")
    .select("id", { count: "exact", head: true })
    .eq("job_id", jobId)
    .eq("status", "accepted");

  if ((acceptedCount ?? 0) > 0) {
    return fail("A technician has already accepted this job", 409);
  }

  const { error: clearError } = await db
    .from("job_matches")
    .delete()
    .eq("job_id", jobId)
    .in("status", ["shortlisted", "offered"]);

  if (clearError) {
    return fail("Could not clear the old matches", 500, clearError.message);
  }

  // Conditional on the state checked above, so an acceptance that landed in
  // the moment between that check and this write cannot be overwritten: the
  // accept moves the job to `confirmed`, this matches no row, and the client
  // is told why.
  const { data: updated, error: updateError } = await db
    .from("jobs")
    .update({ ...update, status: "pending" })
    .eq("id", jobId)
    .in("status", ["pending", "matched"])
    .is("assigned_technician_id", null)
    .select()
    .maybeSingle();

  if (updateError) {
    return updateError.code === "23514"
      ? fail("Some of those details are not valid. Please review them.", 422, updateError.message)
      : fail("Could not save your changes", 500, updateError.message);
  }
  if (!updated) {
    return fail("A technician has just taken this job, so it cannot be edited", 409);
  }

  console.log(
    `job ${jobId}: edited by client ${uid} (${Object.keys(update).join(", ")})`,
  );

  return json({ job_id: jobId, job: updated, status: "pending" });
}
