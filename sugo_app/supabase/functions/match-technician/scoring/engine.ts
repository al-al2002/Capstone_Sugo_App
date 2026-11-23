/**
 * The matching routine itself, independent of HTTP.
 *
 * Kept separate from `index.ts` so two callers can share it:
 *
 * * `match-technician` runs it when a client posts a job.
 * * `job-response` runs it again when all three offers were declined, passing
 *   the decliners in `excludeTechnicianIds` so nobody is re-offered a job they
 *   already turned down.
 *
 * Without this split the cascade would have to call the other function over
 * HTTP, and would then have to forge an identity to pass its ownership check.
 * A shared module keeps one authorisation boundary, in the HTTP handlers.
 */
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

import { HARD_RADIUS_KM, TOP_N } from "./constants.ts";
import { distanceBetween } from "./geo.ts";
import { buildAccuracyIndex, type OutcomeRow } from "./accuracy.ts";
import {
  applyPreviousTechnicianPriority,
  exposureFor,
  rankAll,
  scoreCandidate,
  toConsidered,
} from "./rank.ts";
import { deriveSignals, selectRules } from "./rules.ts";
import {
  type AvailabilityFacts,
  applyClientPreferenceFilter,
  type ClientPreferences,
  type DistanceFallback,
  distanceFallback,
  distanceFallbackMessage,
  NO_AVAILABILITY_FACTS,
  type PreferenceKey,
  readPreferences,
  relaxMessage,
  type RelaxHint,
} from "./preferences.ts";
import type {
  ClientHistory,
  ClientTechnicianHistory,
  ClientTrust,
  ConsideredCandidate,
  ContextSignal,
  JobContext,
  JobRow,
  ScoredCandidate,
  TechnicianRow,
  TrackRecord,
} from "./types.ts";
import { fetchTraffic } from "../clients/tomtom.ts";
import { fetchWeather } from "../clients/openweather.ts";
import { takesWorkFor, workTypeLabel } from "./work_type.ts";

export interface MatchOutcome {
  jobId: string;
  evaluated: number;
  matches: unknown[];
  /**
   * Every technician the engine scored, in rank order - not just the three
   * that fit in `job_matches`. Response-only; nothing here is stored.
   */
  considered: ConsideredCandidate[];
  message: string | null;
  /**
   * True only when the client's own preferences removed every candidate who
   * survived the Stage 1 gates. The app then offers to relax them instead of
   * showing an empty list. False whenever relaxing would not help - nobody
   * verified, everyone beyond the ceiling, everyone already declined.
   */
  noMatchRelaxPreferences: boolean;
  /** What the preference pre-filter did. Absent when no preference was set. */
  preferenceFilter?: {
    active: PreferenceKey[];
    before: number;
    after: number;
    failing: Partial<Record<PreferenceKey, number>>;
    relax_hints: RelaxHint[];
  };
  /**
   * Set when nobody was within the client's distance limit and the engine
   * showed the nearest qualified technicians instead (2026-11-17).
   */
  distanceFallback?: DistanceFallback;
  context: {
    traffic: string | null;
    weather: string | null;
    /** The conditions that held, e.g. ["urgent", "rain", "on_site"]. */
    signals?: ContextSignal[];
    /** Labels of the matching rules that fired, in rule-base order. */
    rules?: string[];
  };
}

/**
 * This client's earlier jobs that had a technician, and the stars they gave.
 *
 * Two small queries on the client's own rows. Failure is not fatal: an empty
 * history is the cold-start case, which the scorer already handles by
 * dropping the preference factor - so the worst outcome of an error here is a
 * ranking that ignores preferences, never a failed match.
 */
async function loadClientHistory(
  db: SupabaseClient,
  job: JobRow,
): Promise<ClientHistory> {
  const empty: ClientHistory = { pastJobs: 0, byTechnician: new Map() };

  const { data: jobs, error } = await db
    .from("jobs")
    .select("id, assigned_technician_id, status")
    .eq("client_id", job.client_id)
    .neq("id", job.id)
    .not("assigned_technician_id", "is", null)
    .returns<{ id: string; assigned_technician_id: string; status: string }[]>();

  if (error) {
    console.warn("client history unavailable:", error.message);
    return empty;
  }
  if (!jobs || jobs.length === 0) return empty;

  const byTechnician = new Map<string, ClientTechnicianHistory>();
  for (const row of jobs) {
    const entry = byTechnician.get(row.assigned_technician_id) ??
      { jobs: 0, completed: 0, stars: null };
    entry.jobs += 1;
    if (row.status === "completed") entry.completed += 1;
    byTechnician.set(row.assigned_technician_id, entry);
  }

  // Newest review first, so each technician keeps the client's latest verdict.
  const { data: reviews, error: reviewError } = await db
    .from("job_reviews")
    .select("technician_id, stars, created_at")
    .eq("reviewer_id", job.client_id)
    .order("created_at", { ascending: false })
    .returns<{ technician_id: string; stars: number }[]>();

  if (reviewError) {
    console.warn("client reviews unavailable:", reviewError.message);
  } else {
    for (const review of reviews ?? []) {
      const entry = byTechnician.get(review.technician_id);
      if (entry && entry.stars === null) entry.stars = review.stars;
    }
  }

  return { pastJobs: jobs.length, byTechnician };
}

/**
 * How each technician in the pool has answered offers: accepted vs declined.
 *
 * Only answered offers count. `shortlisted` never reached them, `offered` is
 * still waiting, and a client withdrawing an offer returns it to
 * `shortlisted` - so a slow reply is never recorded as a refusal.
 */
async function loadTrackRecords(
  db: SupabaseClient,
  poolIds: string[],
): Promise<Map<string, TrackRecord>> {
  const records = new Map<string, TrackRecord>();
  if (poolIds.length === 0) return records;

  const { data, error } = await db
    .from("job_matches")
    .select("technician_id, status")
    .in("technician_id", poolIds)
    .in("status", ["accepted", "declined"])
    .returns<{ technician_id: string; status: string }[]>();

  if (error) {
    // Everyone then sits at the response prior - honest, and survivable.
    console.warn("offer history unavailable:", error.message);
    return records;
  }

  for (const row of data ?? []) {
    const entry = records.get(row.technician_id) ?? { accepted: 0, declined: 0 };
    if (row.status === "accepted") entry.accepted += 1;
    else entry.declined += 1;
    records.set(row.technician_id, entry);
  }
  return records;
}

/**
 * The two availability facts the preference filter cannot read off the
 * candidate row. Queried only for the preference the client set, so a job
 * without an availability preference costs nothing extra.
 *
 * * `now` - on time off today is already on the row (`away_until`); this adds
 *   who is on another unfinished job, by the same definition `job-response`
 *   uses for the busy warning (`confirmed` / `in_progress`).
 * * `on_date` - time off covering that date, inclusive on both ends, the way
 *   `technician_away_until()` reads the table.
 *
 * A failed query applies the preference with no extra facts - for `now`
 * that still excludes anyone on time off - and logs it. Removing everybody
 * because a lookup failed would tell the client their requirements were
 * impossible when they were not. `job-response` re-checks time off live
 * before a booking anyway.
 */
async function loadAvailabilityFacts(
  db: SupabaseClient,
  job: JobRow,
  candidateIds: string[],
  prefs: ClientPreferences,
): Promise<AvailabilityFacts> {
  if (!prefs.availability || candidateIds.length === 0) return NO_AVAILABILITY_FACTS;

  if (prefs.availability === "now") {
    const { data, error } = await db
      .from("jobs")
      .select("assigned_technician_id")
      .in("assigned_technician_id", candidateIds)
      .in("status", ["confirmed", "in_progress"])
      .neq("id", job.id)
      .returns<{ assigned_technician_id: string }[]>();

    if (error) {
      console.warn("busy lookup unavailable:", error.message);
      return NO_AVAILABILITY_FACTS;
    }
    return {
      busy: new Set((data ?? []).map((row) => row.assigned_technician_id)),
      awayOnDate: new Set(),
    };
  }

  const { data, error } = await db
    .from("technician_time_off")
    .select("technician_id")
    .in("technician_id", candidateIds)
    .lte("starts_on", prefs.availableOn)
    .gte("ends_on", prefs.availableOn)
    .returns<{ technician_id: string }[]>();

  if (error) {
    console.warn("time-off lookup unavailable:", error.message);
    return NO_AVAILABILITY_FACTS;
  }
  return {
    busy: new Set(),
    awayOnDate: new Set((data ?? []).map((row) => row.technician_id)),
  };
}

/**
 * Scores the whole verified pool against one job and writes the Top 3.
 *
 * Assumes the caller has already established that whoever triggered this is
 * allowed to. `db` must be a service-role client: ranking requires reading
 * every technician, which `technicians_select_own` forbids for a normal user.
 */
export async function runMatching(
  db: SupabaseClient,
  job: JobRow,
  excludeTechnicianIds: string[] = [],
): Promise<MatchOutcome> {
  const exclude = new Set(excludeTechnicianIds);

  // ------------------------------------------------------ the candidate pool
  //
  // Reads `matching_candidates`, which pre-joins the profile, the identity
  // verdict, the base location, the service radius, the verification tier and
  // the declared specialisations. One query for everything both stages need.
  const { data: technicians, error: poolError } = await db
    .from("matching_candidates")
    .select("*")
    // ---------------------------------------------------- Stage 1 hard gates
    //
    // Two gates, both about trust, both required.
    //
    // `is_verified`  - permanent, set by SUGO. Are they allowed to work at all?
    // `identity_approved` - a human approved their ID + selfie.
    //
    // The identity gate is not redundant with `is_verified`, even though
    // `activate_account()` sets them together today. They mean different
    // things - one is "cleared to work", the other is "we know who this is" -
    // and an unverified identity must never reach a client's doorstep because
    // some future change moved one flag without the other. Cheap to assert,
    // catastrophic to assume.
    //
    // Availability is deliberately not a gate. It was once `is_available`, the
    // online switch; since 2026-09-22 it is time off (`away_until`), and the
    // switch is no longer read at all. Either way, being unavailable is a
    // statement about today, not about whether someone should ever be shown -
    // excluding on it gave a client whose only nearby expert was away an
    // empty Top 3 with no explanation. It is the heaviest factor in Stage 2
    // and a label on the card instead, and `job-response` refuses the booking.
    .eq("is_verified", true)
    .eq("identity_approved", true)
    .returns<TechnicianRow[]>();

  if (poolError) throw new Error(`Could not load technicians: ${poolError.message}`);

  // The work-type gate (2026-11-17): only technicians who take this kind of
  // work - Home Service or Shop Repair - are considered. See `work_type.ts`.
  const verified = (technicians ?? []).filter((t) => !exclude.has(t.id));
  const pool = verified.filter((t) => takesWorkFor(t, job.service_path));

  if (pool.length === 0) {
    return {
      jobId: job.id,
      evaluated: 0,
      matches: [],
      considered: [],
      message: verified.length > 0
        ? `No verified technician takes ${workTypeLabel(job.service_path)} ` +
          "jobs yet. You can switch the service type and search again."
        : exclude.size > 0
        ? "Every available technician has already been offered this job."
        : "No ID-verified technicians on the platform yet.",
      noMatchRelaxPreferences: false,
      context: { traffic: null, weather: null },
    };
  }

  // Which specialisation device types can serve this job. Computed in SQL so
  // the coarse/fine vocabulary bridge lives in exactly one place.
  //
  // Fetched before the gates below, because the "Skill verified" trust
  // preference is measured against these devices.
  const { data: deviceRow } = await db.rpc("job_device_candidates", {
    p_device_type: job.device_type,
    p_device_detail: job.device_detail,
  });

  const deviceCandidates: string[] = Array.isArray(deviceRow) ? deviceRow : [];

  // ------------------------------------------- distance, once per technician
  //
  // Measured from the technician's BASE, not their live `latitude`.
  //
  // `technicians.latitude` is a working position: it is null for anyone not
  // currently on a job, and stale for anyone who finished one. Ranking on it
  // meant a technician who had never worked had no distance at all, and one
  // who had was ranked from wherever they happened to last be. Since
  // registration now captures `base_latitude/base_longitude`, distance and
  // ETA come from where they actually operate.
  //
  // The live position is still carried in the snapshot for the tracking map;
  // it is simply not what ranking is based on.
  //
  // Computed once here because two gates and the scorer all need it.
  const distances = new Map<string, number | null>();
  for (const technician of pool) {
    distances.set(
      technician.id,
      distanceBetween(
        job.latitude,
        job.longitude,
        technician.base_latitude ?? technician.latitude,
        technician.base_longitude ?? technician.longitude,
      ),
    );
  }

  // ------------------------------------------ Stage 1 hard gate: the ceiling
  //
  // Being outside a technician's own declared radius is not an exclusion. It
  // is scored by `coverageFitScore` (Table 11's Coverage fit), which is given
  // the radius and decays toward zero past it, and by Travel burden, which
  // grows with every extra kilometre. Deleting these candidates was handing clients
  // an empty Top 3 whenever every nearby technician happened to be a little
  // further out than they had declared, which is worse than showing them
  // ranked last with "past their 10 km service area" printed on the card.
  //
  // The absolute ceiling stays a hard cut. Even a technician who typed 100 km
  // is not a sensible call-out across a province, and no amount of rating
  // makes a 60 km trip a repair the client can use. An unknown distance is
  // kept, as it always was: its travel and coverage signals are null, and
  // their weight goes to the signals that can be measured.
  const withinCeiling = pool.filter((technician) => {
    const distanceKm = distances.get(technician.id) ?? null;
    return distanceKm === null || distanceKm <= HARD_RADIUS_KM;
  });
  const beyondCeiling = pool.length - withinCeiling.length;

  if (withinCeiling.length === 0) {
    return {
      jobId: job.id,
      evaluated: 0,
      matches: [],
      considered: [],
      message: `No technician is within ${HARD_RADIUS_KM} km of this job. ` +
        `${beyondCeiling} ${beyondCeiling === 1 ? "was" : "were"} further ` +
        `away than that.`,
      // Relaxing a preference cannot bring back someone 60 km away.
      noMatchRelaxPreferences: false,
      context: { traffic: null, weather: null },
    };
  }

  // ------------------------------------ client preference pre-filter (NEW)
  //
  // The client's own minimum requirements, as hard gates. Runs AFTER the
  // Stage 1 gates and BEFORE any context or scoring, so a technician who
  // fails one is removed from the pool rather than ranked low - and never
  // influences the ranking of anyone else. Nothing set => `kept` is
  // `withinCeiling`, unchanged. See `preferences.ts`.
  const preferences = readPreferences(job);
  const availabilityFacts = await loadAvailabilityFacts(
    db,
    job,
    withinCeiling.map((technician) => technician.id),
    preferences,
  );
  const filter = applyClientPreferenceFilter(
    withinCeiling,
    distances,
    preferences,
    deviceCandidates,
    availabilityFacts,
  );
  // Nobody within the distance limit, but someone just beyond it who meets
  // everything else: show them, and say so (2026-11-17, the user's request).
  const fallback = distanceFallback(
    filter,
    withinCeiling,
    distances,
    preferences,
    deviceCandidates,
    availabilityFacts,
  );
  const candidates = fallback?.kept ?? filter.kept;
  if (fallback) {
    console.log(
      `job ${job.id}: nobody within ${fallback.fallback.wanted_km} km; ` +
        `showing ${candidates.length} from ${fallback.fallback.nearest_km} km`,
    );
  }

  const preferenceFilter = filter.active.length === 0 ? undefined : {
    active: filter.active,
    before: filter.before,
    after: candidates.length,
    failing: filter.failing,
    relax_hints: filter.relaxHints,
  };

  if (filter.active.length > 0) {
    console.log(
      `job ${job.id}: preferences=[${filter.active.join(",")}] ` +
        `kept=${candidates.length}/${filter.before} ` +
        `failing=${JSON.stringify(filter.failing)}`,
    );
  }

  if (candidates.length === 0) {
    // Edge case from the brief: the preferences left nobody. Nothing is
    // written - the old shortlist, if any, stays until a run that finds
    // someone replaces it - and the flag tells the app to offer relaxing
    // them instead of showing an empty list.
    return {
      jobId: job.id,
      evaluated: 0,
      matches: [],
      considered: [],
      message: relaxMessage(filter, preferences),
      noMatchRelaxPreferences: true,
      preferenceFilter,
      context: { traffic: null, weather: null },
    };
  }

  // ------------------------------- live context, fetched once, shared by all
  const [traffic, weather] = await Promise.all([
    fetchTraffic(job.latitude, job.longitude),
    fetchWeather(job.latitude, job.longitude),
  ]);

  // Who is asking. Read from `job_client_trust`, which defaults a client with
  // no row yet to 'new' rather than returning nothing.
  const { data: trustRow } = await db
    .from("job_client_trust")
    .select("trust_level, no_show_count, avg_rating_from_technicians")
    .eq("job_id", job.id)
    .maybeSingle();

  const clientTrust: ClientTrust = {
    trustLevel: (trustRow?.trust_level ?? "new") as ClientTrust["trustLevel"],
    noShowCount: trustRow?.no_show_count ?? 0,
    averageRating: trustRow?.avg_rating_from_technicians ?? null,
  };

  const servicePath = job.service_path ?? "home_service";

  // ------------------------------------ Steps 2 and 3: context, then rules
  //
  // Signals are derived once for the job, and the rules they select re-weight
  // every candidate identically - the situation is the client's, not the
  // technician's.
  const signals = deriveSignals(job, servicePath, traffic, weather);
  const rules = selectRules(signals);

  // History is loaded for the whole Stage 1 pool, as it was before the
  // preference filter existed - not just for `candidates`. Per-technician it
  // makes no difference; keeping the query identical is the cheapest way to
  // guarantee a job with no preferences ranks exactly as it used to.
  const poolIds = pool.map((t) => t.id);
  const [clientHistory, trackRecords] = await Promise.all([
    loadClientHistory(db, job),
    loadTrackRecords(db, poolIds),
  ]);

  const context: JobContext = {
    traffic,
    weather,
    servicePath,
    travelExposure: exposureFor(job.service_path),
    clientTrust,
    deviceCandidates,
    rules,
    clientHistory,
  };

  console.log(
    `job ${job.id}: pool=${pool.length} excluded=${exclude.size} ` +
      `path=${servicePath} brand=${job.brand ?? "any"} ` +
      `devices=[${deviceCandidates.join(",")}] ` +
      `client_trust=${clientTrust.trustLevel} ` +
      `client_history=${clientHistory.pastJobs} ` +
      `traffic=${traffic.available ? traffic.label : "n/a"} ` +
      `weather=${weather.available ? weather.description : "n/a"} ` +
      `signals=[${signals.join(",")}] ` +
      `rules=[${rules.applied.map((r) => r.id).join(",")}]`,
  );

  // ---------------------------------------------- feedback history, one query
  const { data: outcomes, error: outcomeError } = await db
    .from("job_outcomes")
    .select(
      "technician_id, diagnosis_correct, rerouted_mid_job, final_rating, " +
        "jobs!inner(device_type, problem_symptom)",
    )
    .in("technician_id", poolIds)
    .returns<OutcomeRow[]>();

  if (outcomeError) {
    // History is an input, not a requirement. Without it every technician
    // scores at the prior, which is survivable and honest.
    console.warn("outcome history unavailable:", outcomeError.message);
  }

  const accuracyIndex = buildAccuracyIndex(outcomes ?? [], job);

  // -------------------------------------------------------------- score them
  //
  // Only the technicians who passed both the Stage 1 gates and the client's
  // preferences. Distance comes from the map built above, so the number that
  // gated a technician is the number they are scored on.
  const scored: ScoredCandidate[] = candidates.map((technician) =>
    scoreCandidate(
      job,
      technician,
      context,
      distances.get(technician.id) ?? null,
      accuracyIndex,
      trackRecords,
    )
  );

  // Rank the whole pool once. The first three become offers; the rest exist
  // only in the response, because `job_matches.rank` cannot hold a fourth.
  // Step 5, Previous Provider Priority: a technician this client booked and
  // was happy with goes first, if they are in today's pool at all.
  const ranked = applyPreviousTechnicianPriority(
    rankAll(scored),
    context.clientHistory,
  );
  const top = ranked.slice(0, TOP_N);
  const offeredIds = new Set(top.map((candidate) => candidate.technician.id));

  const considered = ranked.map((candidate, index) =>
    toConsidered(candidate, index, offeredIds.has(candidate.technician.id))
  );

  // ------------------------------------------------------- write shortlist
  // Remove outstanding rows first: `rank` is constrained to 1-3, so a re-run
  // would otherwise produce two rows claiming rank 1 for one job.
  //
  // Both open states are cleared. `declined` and `accepted` are history and are
  // kept - the decline cascade reads them back to exclude technicians who
  // already said no.
  const { error: clearError } = await db
    .from("job_matches")
    .delete()
    .eq("job_id", job.id)
    .in("status", ["shortlisted", "offered"]);

  if (clearError) console.warn("could not clear stale offers:", clearError.message);

  const rows = top.map((candidate, index) => ({
    job_id: job.id,
    technician_id: candidate.technician.id,
    rank: index + 1,
    suitability_score: candidate.suitability.score,
    acceptance_score: candidate.acceptance.score,
    final_score: candidate.finalScore,
    // The fallback rides on each row, so the app can explain it on any later
    // visit to this shortlist, not only on the run that produced it.
    score_breakdown: fallback
      ? { ...candidate.breakdown, preference_fallback: fallback.fallback }
      : candidate.breakdown,
    // NOT "offered". These three are the client's shortlist; none of them
    // reaches a technician's dashboard until the client selects one, which is
    // what promotes that single row to `offered`. Writing `offered` here is the
    // bug this replaced - it put one job on three dashboards at once, none of
    // whom had been booked.
    status: "shortlisted",
  }));

  const { data: inserted, error: insertError } = await db
    .from("job_matches")
    .insert(rows)
    .select();

  if (insertError) {
    throw new Error(`Could not save the matches: ${insertError.message}`);
  }

  // Only nudge a pending job forward. A job already `confirmed` must not be
  // dragged back to `matched` by a re-run.
  const { error: statusError } = await db
    .from("jobs")
    .update({ status: "matched" })
    .eq("id", job.id)
    .eq("status", "pending");

  if (statusError) console.warn("could not move job to matched:", statusError.message);

  return {
    jobId: job.id,
    evaluated: scored.length,
    matches: inserted ?? [],
    considered,
    message: fallback ? distanceFallbackMessage(fallback.fallback) : null,
    noMatchRelaxPreferences: false,
    preferenceFilter,
    distanceFallback: fallback?.fallback,
    context: {
      traffic: traffic.available ? traffic.label : null,
      weather: weather.available ? weather.description : null,
      signals,
      rules: rules.applied.map((rule) => rule.label),
    },
  };
}
