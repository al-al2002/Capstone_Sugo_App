-- =============================================================================
-- SUGO: Progressive Trust Badge (2026-11-15)
-- =============================================================================
--
-- A technician moves up an ordered ladder by meeting objective criteria, and
-- down it when a dispute or their own record says so:
--
--   1. id_verified        identity approved (ID + selfie) and email confirmed
--   2. skill_verified     at least one specialisation proven, by a passed
--                         assessment or an admin-approved certificate
--   3. community_trusted  skill verified, and a track record: 50+ completed
--                         jobs, 4.5+ rating, 90%+ response rate, no open or
--                         upheld disputes against them, under 10% cancellations
--
-- Rule-based throughout: `trust_badge_level()` below is a handful of explicit
-- comparisons. No model, no learned weights.
--
-- ## One source of truth
--
-- The level is written to `technicians.badge` - an EXISTING column, already
-- protected from the technician by `guard_technician_self_update` and already
-- read by the matcher, the listings and the app. Which specialisations are
-- skill verified is NOT stored a second time: it is
-- `technician_specializations.verified`, which the assessment, the
-- certificate review and dispute de-verification all write. The client
-- preference filter, Stage 1's trust factor and the profile all read those
-- two things and nothing else.
--
-- ## Approved by the user, 2026-11-15
--
-- The schema is otherwise frozen. Approved for this feature:
--   * job_matches.offered_at / responded_at - so the 24 h response window is
--     measurable at all (nothing recorded when an offer was sent)
--   * offer_misses - a trigger-written log, so an ignored offer survives the
--     client re-matching or editing the job (both delete open matches)
--   * job_disputes.outcome / remedy / remedy_specialization - "lost" and
--     "skill de-verification" were not recordable before
--   * technician_verification_documents.specialization - so a certificate
--     can prove ONE specialisation, as the brief requires
--   * the level in the existing technicians.badge column
--
-- ## Adapted from the brief, and why
--
--   * No phone check in ID Verified: phone verification was removed from the
--     app in 20260909000001 (no free SMS route). Email confirmation is the
--     contact check that exists.
--   * Cancellation rate is computed but is 0 for everyone: a technician
--     cannot cancel a job after accepting it anywhere in the app. The rule is
--     wired so it means something the day such an action exists.
--   * Recompute is event-driven through Postgres triggers, not Laravel: the
--     events (completion, review, dispute decision, offer answer, assessment,
--     certificate) are written by edge functions, SQL functions AND the admin
--     console. A trigger is the one place all of them pass through. A nightly
--     pg_cron sweep catches the one thing no event announces: an offer
--     crossing the 24 h window while nobody touches it.
--
-- ## After applying this
--
--   supabase db push
--   supabase functions deploy match-technician job-response
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. The rules, in one place
-- ---------------------------------------------------------------------------
--
-- Named, not scattered: every threshold the panel can ask about is here, and
-- the technician's progress card reads the same row.

create or replace function public.trust_badge_rules()
returns table (
  min_completed_jobs    integer,
  min_avg_rating        numeric,
  min_response_rate     numeric,
  max_disputes          integer,
  max_cancellation_rate numeric,
  response_window       interval
)
language sql
immutable
as $function$
  select
    50,                    -- completed_jobs      >= 50
    4.5::numeric,          -- avg_rating          >= 4.5
    0.90::numeric,         -- response_rate       >= 90%
    0,                     -- open or lost disputes == 0
    0.10::numeric,         -- cancellation_rate   <  10%
    interval '24 hours';   -- an answer later than this counts as no answer
$function$;

comment on function public.trust_badge_rules() is
  'Community Trusted thresholds and the offer response window. The one place '
  'they are defined; the evaluator and the progress card both read it.';

-- The ladder itself, as a pure function of the measurements.
--
-- Pure so it can be tested on its own and read in one breath at a defence.
-- Each rung requires the one below it, which is what makes `>=` comparisons
-- between levels meaningful anywhere else in the system.
create or replace function public.trust_badge_level(
  p_identity_approved boolean,
  p_email_confirmed   boolean,
  p_skill_count       integer,
  p_completed_jobs    integer,
  p_avg_rating        numeric,
  p_response_rate     numeric,
  p_disputes          integer,
  p_cancellation_rate numeric
)
returns text
language plpgsql
immutable
as $function$
declare
  r record;
begin
  select * into r from public.trust_badge_rules();

  -- Below the baseline there is no badge at all. Losing it is never an
  -- automatic downgrade: it only happens when an admin changes the identity
  -- decision, which is also what suspends job acceptance.
  if not (coalesce(p_identity_approved, false) and coalesce(p_email_confirmed, false)) then
    return null;
  end if;

  if coalesce(p_skill_count, 0) < 1 then
    return 'id_verified';
  end if;

  if coalesce(p_completed_jobs, 0)    >= r.min_completed_jobs
     and coalesce(p_avg_rating, 0)    >= r.min_avg_rating
     and coalesce(p_response_rate, 0) >= r.min_response_rate
     and coalesce(p_disputes, 0)      <= r.max_disputes
     and coalesce(p_cancellation_rate, 0) < r.max_cancellation_rate
  then
    return 'community_trusted';
  end if;

  return 'skill_verified';
end;
$function$;

comment on function public.trust_badge_level(boolean, boolean, integer, integer, numeric, numeric, integer, numeric) is
  'The Progressive Trust Badge ladder as explicit comparisons. Null below ID '
  'Verified; each rung requires the one below.';


-- ---------------------------------------------------------------------------
-- 2. The five client-facing specialisations
-- ---------------------------------------------------------------------------
--
-- The same vocabulary as `jobs.pref_specialization` and the app's
-- `PreferredSpecialization`, mapped onto `technician_specializations.
-- device_type`. One definition, so "Skill Verified for Phone/Tablet" means the
-- same thing to the filter, the badge and the dispute remedy.

create or replace function public.specialization_devices(p_specialization text)
returns text[]
language sql
immutable
as $function$
  select case p_specialization
    when 'computer'      then array['laptop', 'desktop']
    when 'phone_tablet'  then array['smartphone', 'tablet']
    when 'network_setup' then array['router', 'cctv', 'printer']
    when 'appliance'     then array['aircon', 'refrigerator', 'washing_machine',
                                    'television', 'microwave']
    when 'pc_building'   then array['desktop']
    else array[]::text[]
  end;
$function$;

-- Which of the five a technician is skill verified for. Derived, never
-- stored: the verified flags on their specialisations are the record.
create or replace function public.skill_verified_specializations(p_technician_id uuid)
returns text[]
language sql
stable
security definer
set search_path = public
as $function$
  select coalesce(array_agg(s.spec order by s.ord), array[]::text[])
  from unnest(array['computer', 'pc_building', 'phone_tablet', 'network_setup',
                    'appliance']) with ordinality as s(spec, ord)
  where exists (
    select 1
    from public.technician_specializations ts
    where ts.technician_id = p_technician_id
      and ts.verified
      and ts.device_type = any(public.specialization_devices(s.spec))
  );
$function$;

revoke all on function public.skill_verified_specializations(uuid) from public, anon;
grant execute on function public.skill_verified_specializations(uuid) to authenticated, service_role;


-- ---------------------------------------------------------------------------
-- 3. The offer clock and missed offers
-- ---------------------------------------------------------------------------
--
-- response_rate = offers answered within 24 h / every offer that was answered,
-- ignored, or is still waiting past 24 h. Before this, nothing recorded WHEN
-- an offer was sent or answered, and an ignored offer left no trace once the
-- client withdrew it (`withdraw_technician_offer` returns it to `shortlisted`)
-- or re-matched / edited the job (both delete open matches).

alter table public.job_matches
  add column if not exists offered_at   timestamptz,
  add column if not exists responded_at timestamptz;

comment on column public.job_matches.offered_at is
  'When the client sent this offer (status became offered). Set by trigger.';
comment on column public.job_matches.responded_at is
  'When the technician accepted or declined. Set by trigger.';

-- Offers already waiting start their clock now, rather than being judged
-- against a send time nobody recorded.
update public.job_matches
set offered_at = now()
where status = 'offered' and offered_at is null;

create table if not exists public.offer_misses (
  id            uuid primary key default gen_random_uuid(),
  technician_id uuid not null references public.technicians(id) on delete cascade,
  -- No foreign key: the miss must outlive the job if the client deletes it.
  job_id        uuid not null,
  offered_at    timestamptz not null,
  recorded_at   timestamptz not null default now(),
  -- withdrawn = the client took it back; cleared = re-match, edit or delete.
  how           text not null check (how in ('withdrawn', 'cleared'))
);

comment on table public.offer_misses is
  'Offers a technician left unanswered for longer than the response window, '
  'kept after the job_matches row is reset or deleted. Written only by the '
  'job_matches_offer_clock trigger; counts against response_rate.';

create index if not exists offer_misses_technician_idx
  on public.offer_misses (technician_id);

alter table public.offer_misses enable row level security;
-- No policies: nobody reads or writes it directly. The evaluator and the
-- progress RPC read it as definer.
revoke all on public.offer_misses from anon, authenticated;

create or replace function public.job_matches_offer_clock()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_window interval := (select response_window from public.trust_badge_rules());
begin
  if tg_op = 'INSERT' then
    if new.status = 'offered' then
      new.offered_at := coalesce(new.offered_at, now());
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    -- Re-match, "Edit post" or deleting the job while an offer had been
    -- ignored past the window: still a miss.
    if old.status = 'offered'
       and old.responded_at is null
       and old.offered_at is not null
       and old.offered_at <= now() - v_window
    then
      insert into public.offer_misses (technician_id, job_id, offered_at, how)
      values (old.technician_id, old.job_id, old.offered_at, 'cleared');
    end if;
    return old;
  end if;

  -- UPDATE
  if new.status = 'offered' and old.status is distinct from 'offered' then
    -- A fresh offer, including re-offering someone after a withdrawal.
    new.offered_at := now();
    new.responded_at := null;

  elsif old.status = 'offered' and new.status in ('accepted', 'declined') then
    new.responded_at := coalesce(new.responded_at, now());

  elsif old.status = 'offered' and new.status = 'shortlisted' then
    -- The client withdrew it. Only a miss if the technician had already had
    -- the full window: a client who changes their mind after five minutes
    -- says nothing about the technician (the same fairness rule
    -- `withdraw_technician_offer` gives for not recording a decline).
    if old.offered_at is not null and old.offered_at <= now() - v_window then
      insert into public.offer_misses (technician_id, job_id, offered_at, how)
      values (old.technician_id, old.job_id, old.offered_at, 'withdrawn');
    end if;
    new.offered_at := null;
  end if;

  return new;
end;
$function$;

drop trigger if exists job_matches_offer_clock on public.job_matches;
create trigger job_matches_offer_clock
  before insert or update of status or delete on public.job_matches
  for each row execute function public.job_matches_offer_clock();


-- ---------------------------------------------------------------------------
-- 4. Dispute outcome and remedy
-- ---------------------------------------------------------------------------
--
-- `status` stays as it was (open / resolved / dismissed). Added beside it:
--   outcome               upheld = the reporter was right; not_upheld
--   remedy                none | skill_deverification
--   remedy_specialization which of the five the remedy removes
--
-- A dispute is "lost" by the technician when a CLIENT raised it and it was
-- upheld. Open client reports count too, as the brief asks.

alter table public.job_disputes
  add column if not exists outcome               text,
  add column if not exists remedy                text,
  add column if not exists remedy_specialization text;

alter table public.job_disputes drop constraint if exists job_disputes_outcome_values;
alter table public.job_disputes add constraint job_disputes_outcome_values
  check (outcome is null or outcome in ('upheld', 'not_upheld'));

alter table public.job_disputes drop constraint if exists job_disputes_remedy_values;
alter table public.job_disputes add constraint job_disputes_remedy_values
  check (remedy is null or remedy in ('none', 'skill_deverification'));

alter table public.job_disputes drop constraint if exists job_disputes_remedy_specialization_values;
alter table public.job_disputes add constraint job_disputes_remedy_specialization_values
  check (remedy_specialization is null or remedy_specialization in (
    'computer', 'phone_tablet', 'network_setup', 'appliance', 'pc_building'
  ));

-- Decisions made before today: "Mark resolved" meant action was taken, so it
-- reads as upheld; "Close without action" as not upheld. No remedy existed.
update public.job_disputes
set outcome = case when status = 'resolved' then 'upheld' else 'not_upheld' end,
    remedy = 'none'
where status <> 'open' and outcome is null;

alter table public.job_disputes drop constraint if exists job_disputes_finding_consistent;
alter table public.job_disputes add constraint job_disputes_finding_consistent check (
  (status = 'open' and outcome is null and remedy is null and remedy_specialization is null)
  or (status = 'dismissed' and outcome = 'not_upheld' and remedy = 'none'
      and remedy_specialization is null)
  or (status = 'resolved' and outcome is not null and remedy is not null)
);

alter table public.job_disputes drop constraint if exists job_disputes_remedy_shape;
alter table public.job_disputes add constraint job_disputes_remedy_shape check (
  (remedy is distinct from 'skill_deverification'
     or (outcome = 'upheld' and raised_by_role = 'client'
         and remedy_specialization is not null))
  and (remedy is distinct from 'none' or remedy_specialization is null)
);

-- The admin queue, with the new columns appended (a view can only grow at the
-- end without being dropped).
create or replace view public.admin_disputes as
select
  d.id,
  d.job_id,
  d.created_at,
  d.status,
  d.reason,
  d.details,
  d.photo_paths,
  d.raised_by,
  d.raised_by_role,
  pr.full_name          as raised_by_name,
  d.resolution_note,
  d.resolved_at,
  pa.full_name          as resolved_by_name,
  j.device_type,
  j.brand,
  j.problem_symptom,
  j.status              as job_status,
  j.client_id,
  pc.full_name          as client_name,
  j.assigned_technician_id as technician_id,
  pt.full_name          as technician_name,
  d.outcome,
  d.remedy,
  d.remedy_specialization
from public.job_disputes d
join public.jobs j       on j.id = d.job_id
join public.profiles pr  on pr.id = d.raised_by
join public.profiles pc  on pc.id = j.client_id
left join public.profiles pt on pt.id = j.assigned_technician_id
left join public.profiles pa on pa.id = d.resolved_by;

revoke all on table public.admin_disputes from anon, authenticated;


-- ---------------------------------------------------------------------------
-- 5. A de-verification must stick
-- ---------------------------------------------------------------------------
--
-- Two existing paths would otherwise undo it:
--   * `inherit_track_verification` re-verifies a re-added specialisation from
--     an old passing assessment - delete and re-add, and the remedy is gone;
--   * `record_assessment_result` refuses to re-sit a track already passed -
--     so a de-verified technician could never earn it back.
-- The rule both now follow: a pass only counts if it was taken AFTER the most
-- recent de-verification covering that device.

create or replace function public.skill_deverified_at(
  p_technician_id uuid,
  p_device_type text
)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $function$
  select coalesce(max(d.resolved_at), '-infinity'::timestamptz)
  from public.job_disputes d
  join public.jobs j on j.id = d.job_id
  where j.assigned_technician_id = p_technician_id
    and d.remedy = 'skill_deverification'
    and p_device_type = any(public.specialization_devices(d.remedy_specialization));
$function$;

-- The same, for every device in an assessment track.
create or replace function public.track_deverified_at(
  p_technician_id uuid,
  p_track text
)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $function$
  select coalesce(max(d.resolved_at), '-infinity'::timestamptz)
  from public.job_disputes d
  join public.jobs j on j.id = d.job_id
  where j.assigned_technician_id = p_technician_id
    and d.remedy = 'skill_deverification'
    and exists (
      select 1
      from unnest(public.specialization_devices(d.remedy_specialization)) as dev
      where public.assessment_track(dev) = p_track
    );
$function$;

revoke all on function public.skill_deverified_at(uuid, text) from public, anon, authenticated;
revoke all on function public.track_deverified_at(uuid, text) from public, anon, authenticated;

-- Copied from 20260907000009 with one condition added (marked NEW).
create or replace function public.inherit_track_verification()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_level text;
begin
  -- The most recent passing result for this technician on this track.
  select public.assessment_skill_level(r.score) into v_level
  from public.technician_assessment_results r
  where r.technician_id = new.technician_id
    and r.track = new.track
    and r.passed
    -- NEW (20261115000002): a pass from before a dispute de-verification
    -- covering this device no longer qualifies.
    and r.taken_at > public.skill_deverified_at(new.technician_id, new.device_type)
  order by r.taken_at desc
  limit 1;

  if v_level is not null then
    update public.technician_specializations
    set verified = true,
        skill_level = v_level
    where id = new.id;
  end if;

  return null;  -- AFTER trigger; the return value is ignored.
end;
$function$;

-- Copied from 20260907000008 with the "already passed" check changed (NEW).
create or replace function public.record_assessment_result(
  p_technician_id uuid,
  p_track text,
  p_score numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_last_attempt timestamptz;
  v_last_passed boolean;
  v_attempt integer;
  v_level text;
  v_passed boolean;
  v_cooldown interval := public.assessment_retake_cooldown();
  v_spec_id uuid;
  v_verified_count integer;
begin
  -- The technician must actually hold a specialisation in this track. Without
  -- this a caller could pass any track string and qualify for work they never
  -- declared.
  select id into v_spec_id
  from public.technician_specializations
  where technician_id = p_technician_id and track = p_track
  order by created_at
  limit 1;

  if v_spec_id is null then
    raise exception 'No specialisation in track % for this technician', p_track;
  end if;

  select taken_at, passed into v_last_attempt, v_last_passed
  from public.technician_assessment_results
  where technician_id = p_technician_id and track = p_track
  order by taken_at desc
  limit 1;

  -- NEW (20261115000002): a pass that a dispute de-verification has since
  -- overridden does not block a retake - re-sitting is how the skill is
  -- earned back.
  if v_last_passed
     and v_last_attempt > public.track_deverified_at(p_technician_id, p_track)
  then
    raise exception 'This assessment has already been passed';
  end if;

  if v_last_attempt is not null and v_last_attempt + v_cooldown > now() then
    raise exception 'Retake available at %', v_last_attempt + v_cooldown
      using errcode = '55000';
  end if;

  select coalesce(max(attempt_number), 0) + 1 into v_attempt
  from public.technician_assessment_results
  where technician_id = p_technician_id and track = p_track;

  v_level := public.assessment_skill_level(p_score);
  v_passed := v_level is not null;

  insert into public.technician_assessment_results (
    technician_id, specialization_id, track, score, passed, attempt_number
  )
  values (p_technician_id, v_spec_id, p_track, p_score, v_passed, v_attempt);

  if v_passed then
    -- The whole point of this migration: one pass, every brand in the track.
    update public.technician_specializations
    set skill_level = v_level,
        verified = true
    where technician_id = p_technician_id and track = p_track;

    get diagnostics v_verified_count = row_count;
  else
    v_verified_count := 0;
  end if;

  return jsonb_build_object(
    'passed', v_passed,
    'score', p_score,
    'track', p_track,
    'skill_level', v_level,
    'attempt_number', v_attempt,
    'specializations_verified', v_verified_count,
    'retake_available_at',
      case when v_passed then null else now() + v_cooldown end
  );
end;
$function$;

revoke all on function public.record_assessment_result(uuid, text, numeric)
  from public, anon, authenticated;
grant execute on function public.record_assessment_result(uuid, text, numeric)
  to service_role;


-- ---------------------------------------------------------------------------
-- 6. A certificate can prove one specialisation
-- ---------------------------------------------------------------------------

alter table public.technician_verification_documents
  add column if not exists specialization text;

alter table public.technician_verification_documents
  drop constraint if exists technician_verification_documents_specialization_values;
alter table public.technician_verification_documents
  add constraint technician_verification_documents_specialization_values check (
    specialization is null
    or (doc_type = 'certificate' and specialization in (
      'computer', 'phone_tablet', 'network_setup', 'appliance', 'pc_building'
    ))
  );

comment on column public.technician_verification_documents.specialization is
  'Which specialisation an approved certificate proves (chosen by the admin). '
  'Approving it skill-verifies the technician''s declared rows in it.';

-- Re-created with a fifth, optional parameter. Dropped first: adding a
-- parameter would otherwise leave the old signature behind as an overload.
drop function if exists public.review_verification_document(uuid, boolean, uuid, text);

create function public.review_verification_document(
  p_document_id uuid,
  p_approved boolean,
  p_reviewer_id uuid default null,
  p_notes text default null,
  p_specialization text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_tech uuid;
  v_doc_type text;
  v_now timestamptz := now();
  v_is_active boolean;
  v_has_doc boolean;
  v_verified integer := 0;
begin
  select technician_id, doc_type into v_tech, v_doc_type
  from public.technician_verification_documents
  where id = p_document_id
  for update;

  if v_tech is null then
    raise exception 'No such document: %', p_document_id;
  end if;

  if not p_approved and coalesce(trim(p_notes), '') = '' then
    raise exception 'A rejection must include a reason for the technician';
  end if;

  if p_specialization is not null and (
       v_doc_type <> 'certificate'
       or cardinality(public.specialization_devices(p_specialization)) = 0
     ) then
    raise exception 'Only a certificate can prove a specialisation, and it must be one of the five';
  end if;

  update public.technician_verification_documents
  set status = case when p_approved then 'approved' else 'rejected' end,
      admin_notes = p_notes,
      reviewed_by = p_reviewer_id,
      reviewed_at = v_now,
      specialization = case when p_approved then p_specialization else specialization end
  where id = p_document_id;

  -- Unchanged from 20260907000006: an approved certificate or NBI clearance
  -- still raises verification_tier, which the profile shows.
  select registration_status = 'active' into v_is_active
  from public.profiles where id = v_tech;

  if p_approved and coalesce(v_is_active, false) then
    select exists (
      select 1 from public.technician_verification_documents
      where technician_id = v_tech
        and status = 'approved'
        and doc_type in ('certificate', 'nbi_clearance')
    ) into v_has_doc;

    if v_has_doc then
      update public.technicians
      set verification_tier = 'certified_pro'
      where id = v_tech and verification_tier <> 'certified_pro';
    end if;
  end if;

  -- NEW: proof of competency. Verifies the rows the technician declared in
  -- that specialisation. A certificate is not graded, so it proves the skill
  -- at intermediate unless an assessment already awarded more.
  if p_approved and p_specialization is not null then
    update public.technician_specializations
    set verified = true,
        skill_level = coalesce(skill_level, 'intermediate')
    where technician_id = v_tech
      and device_type = any(public.specialization_devices(p_specialization))
      and (not verified or skill_level is null);

    get diagnostics v_verified = row_count;
  end if;

  return jsonb_build_object(
    'document_id', p_document_id,
    'technician_id', v_tech,
    'approved', p_approved,
    'reviewed_at', v_now,
    'specializations_verified', v_verified
  );
end;
$function$;

revoke all on function public.review_verification_document(uuid, boolean, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.review_verification_document(uuid, boolean, uuid, text, text)
  to service_role;

-- Copied from 20260907000012 with one change (NEW): each document entry may
-- carry a "specialization", passed through to the review above.
create or replace function public.review_applicant(
  p_verification_id uuid,
  p_approved boolean,
  p_reviewer_id uuid default null,
  p_notes text default null,
  p_documents jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user_id uuid;
  v_identity jsonb;
  v_entry jsonb;
  v_doc_id uuid;
  v_decision text;
  v_doc_notes text;
  v_owner uuid;
  v_approved_docs integer := 0;
  v_rejected_docs integer := 0;
begin
  select user_id into v_user_id
  from public.identity_verifications
  where id = p_verification_id;

  if v_user_id is null then
    raise exception 'No such identity verification: %', p_verification_id;
  end if;

  v_identity := public.review_identity_verification(
    p_verification_id, p_approved, p_reviewer_id, p_notes
  );

  for v_entry in select * from jsonb_array_elements(coalesce(p_documents, '[]'::jsonb))
  loop
    v_decision := v_entry ->> 'decision';

    if v_decision not in ('approve', 'reject') then
      continue;  -- 'hold' or anything unrecognised: leave it for later.
    end if;

    v_doc_id := (v_entry ->> 'id')::uuid;

    select technician_id into v_owner
    from public.technician_verification_documents
    where id = v_doc_id;

    if v_owner is null or v_owner <> v_user_id then
      raise exception 'Document % does not belong to this applicant', v_doc_id;
    end if;

    v_doc_notes := nullif(trim(v_entry ->> 'notes'), '');

    if v_doc_notes is null and v_decision = 'reject' then
      v_doc_notes := p_notes;
    end if;

    perform public.review_verification_document(
      v_doc_id, v_decision = 'approve', p_reviewer_id, v_doc_notes,
      nullif(trim(v_entry ->> 'specialization'), '')  -- NEW
    );

    if v_decision = 'approve' then
      v_approved_docs := v_approved_docs + 1;
    else
      v_rejected_docs := v_rejected_docs + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'user_id', v_user_id,
    'identity', v_identity,
    'documents_approved', v_approved_docs,
    'documents_rejected', v_rejected_docs
  );
end;
$function$;

revoke all on function public.review_applicant(uuid, boolean, uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.review_applicant(uuid, boolean, uuid, text, jsonb)
  to service_role;


-- ---------------------------------------------------------------------------
-- 7. Measuring a technician
-- ---------------------------------------------------------------------------
--
-- Every number the ladder needs, from data that already exists. Returned as
-- one document because the progress card shows exactly these numbers - the
-- path is transparent because the technician sees what the evaluator sees.

create or replace function public.technician_badge_metrics(
  p_technician_id uuid,
  -- Leave one dispute out of the count. Only the dispute remedy uses it, to
  -- ask "what level did they hold before THIS report?" - see section 8.
  p_ignore_dispute_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  r record;
  v_identity boolean;
  v_email boolean;
  v_skill text[];
  v_completed integer;
  v_avg numeric;
  v_in_window integer;
  v_late integer;
  v_overdue integer;
  v_missed integer;
  v_offers integer;
  v_response numeric;
  v_disputes integer;
  v_accepted integer;
  v_cancelled integer := 0;
  v_cancel_rate numeric;
begin
  select * into r from public.trust_badge_rules();

  -- (1) ID Verified: an admin approved the ID + selfie, and the email is
  -- confirmed (GoTrue writes email_confirmed_at; nothing else can).
  select exists (
    select 1 from public.identity_verifications
    where user_id = p_technician_id and status = 'approved'
  ) into v_identity;

  select u.email_confirmed_at is not null into v_email
  from auth.users u where u.id = p_technician_id;

  -- (2) Skill Verified, per specialisation.
  v_skill := public.skill_verified_specializations(p_technician_id);

  -- (3) Community Trusted inputs.
  select count(*) into v_completed
  from public.jobs
  where assigned_technician_id = p_technician_id and status = 'completed';

  -- The same mean `recompute_technician_rating` writes to technicians.rating,
  -- read from its source so trigger order cannot make it stale.
  select round(avg(o.final_rating)::numeric, 2) into v_avg
  from public.job_outcomes o
  where o.technician_id = p_technician_id and o.final_rating is not null;

  -- Answers before 20261115000002 have no timestamps; they count as answered
  -- in time, because the technician did answer and nobody recorded when.
  select
    count(*) filter (
      where status in ('accepted', 'declined')
        and (offered_at is null or responded_at is null
             or responded_at - offered_at <= r.response_window)),
    count(*) filter (
      where status in ('accepted', 'declined')
        and offered_at is not null and responded_at is not null
        and responded_at - offered_at > r.response_window),
    count(*) filter (
      where status = 'offered'
        and offered_at is not null
        and offered_at <= now() - r.response_window)
  into v_in_window, v_late, v_overdue
  from public.job_matches
  where technician_id = p_technician_id;

  select count(*) into v_missed
  from public.offer_misses where technician_id = p_technician_id;

  v_offers := v_in_window + v_late + v_overdue + v_missed;
  v_response := case when v_offers = 0 then null
                     else round(v_in_window::numeric / v_offers, 4) end;

  -- Reports AGAINST the technician: raised by the client on a job they were
  -- assigned to, and either still open or upheld.
  select count(*) into v_disputes
  from public.job_disputes d
  join public.jobs j on j.id = d.job_id
  where j.assigned_technician_id = p_technician_id
    and d.raised_by_role = 'client'
    and (d.status = 'open' or d.outcome = 'upheld')
    and d.id is distinct from p_ignore_dispute_id;

  -- Technician-initiated cancellations after acceptance / accepted jobs.
  -- No such action exists in the app, so the numerator is 0 by
  -- construction; the denominator is real.
  select count(*) into v_accepted
  from public.job_matches
  where technician_id = p_technician_id and status = 'accepted';

  v_cancel_rate := case when v_accepted = 0 then 0
                        else round(v_cancelled::numeric / v_accepted, 4) end;

  return jsonb_build_object(
    'level', public.trust_badge_level(
      v_identity, coalesce(v_email, false), cardinality(v_skill),
      v_completed, v_avg, v_response, v_disputes, v_cancel_rate
    ),
    'identity_approved', v_identity,
    'email_confirmed', coalesce(v_email, false),
    'skill_verified_specializations', to_jsonb(v_skill),
    'completed_jobs', v_completed,
    'avg_rating', v_avg,
    'response_rate', v_response,
    'offers_counted', v_offers,
    'offers_answered_in_time', v_in_window,
    'disputes_open_or_lost', v_disputes,
    'accepted_jobs', v_accepted,
    'cancellation_rate', v_cancel_rate,
    'thresholds', jsonb_build_object(
      'completed_jobs', r.min_completed_jobs,
      'avg_rating', r.min_avg_rating,
      'response_rate', r.min_response_rate,
      'max_disputes', r.max_disputes,
      'max_cancellation_rate', r.max_cancellation_rate,
      'response_window_hours', extract(epoch from r.response_window) / 3600
    )
  );
end;
$function$;

revoke all on function public.technician_badge_metrics(uuid, uuid) from public, anon, authenticated;

-- Recompute one technician and write the level if it changed.
create or replace function public.evaluate_technician_badge(p_technician_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_level text;
begin
  if p_technician_id is null
     or not exists (select 1 from public.technicians where id = p_technician_id)
  then
    return null;
  end if;

  v_level := public.technician_badge_metrics(p_technician_id) ->> 'level';

  -- Tells `guard_technician_self_update` this change comes from the
  -- evaluator. Needed when the triggering event was the technician's own
  -- action (e.g. removing a specialisation), where auth.uid() IS the
  -- technician and the guard would otherwise refuse the badge change and
  -- abort their whole request. Transaction-local, and reset straight after.
  perform set_config('sugo.badge_eval', 'on', true);

  update public.technicians
  set badge = v_level
  where id = p_technician_id and badge is distinct from v_level;

  perform set_config('sugo.badge_eval', 'off', true);

  return v_level;
end;
$function$;

revoke all on function public.evaluate_technician_badge(uuid) from public, anon, authenticated;
grant execute on function public.evaluate_technician_badge(uuid) to service_role;

-- The nightly sweep, and the backfill below.
create or replace function public.evaluate_all_technician_badges()
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_id uuid;
  v_count integer := 0;
begin
  for v_id in select id from public.technicians loop
    perform public.evaluate_technician_badge(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

revoke all on function public.evaluate_all_technician_badges() from public, anon, authenticated;
grant execute on function public.evaluate_all_technician_badges() to service_role;

-- The technician's own progress card. Re-evaluates first, so the badge they
-- see is never behind the numbers beside it.
create or replace function public.my_trust_badge()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (select 1 from public.technicians where id = v_uid) then
    raise exception 'Only a technician has a trust badge' using errcode = '42501';
  end if;

  perform public.evaluate_technician_badge(v_uid);
  return public.technician_badge_metrics(v_uid);
end;
$function$;

revoke all on function public.my_trust_badge() from public, anon;
grant execute on function public.my_trust_badge() to authenticated;


-- ---------------------------------------------------------------------------
-- 8. Dispute remedy: skill de-verification drops ONE level
-- ---------------------------------------------------------------------------

-- "One level" is measured from the level the technician held WITHOUT this
-- report. That matters because an open client report already costs
-- Community Trusted (the brief counts unresolved disputes), so by the time
-- the admin decides it, the live level reads skill_verified - and removing a
-- skill on top would be two levels for one dispute. (Found by testing the
-- migration in PGlite, 2026-11-15.)
--   community_trusted -> skill_verified. The upheld finding itself keeps
--     Community Trusted away (an upheld client report fails the "no lost
--     disputes" rule), so no skill is taken away - one level, not two.
--   skill_verified -> id_verified FOR THAT SPECIALISATION: its rows lose
--     verified and skill_level. Other specialisations are untouched, so the
--     technician may stay skill verified overall.
-- Never below ID Verified: nothing here touches identity.
create or replace function public.apply_dispute_deverification(
  p_technician_id uuid,
  p_specialization text,
  -- The report the remedy comes from, left out when reading the level
  -- before it. Optional so the brief's two-argument call still works.
  p_dispute_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_level text;
  v_rows integer;
begin
  if cardinality(public.specialization_devices(p_specialization)) = 0 then
    raise exception 'Unknown specialisation: %', p_specialization;
  end if;

  v_level := public.technician_badge_metrics(p_technician_id, p_dispute_id) ->> 'level';

  if v_level = 'community_trusted' then
    return 'community_trusted_to_skill_verified';
  end if;

  update public.technician_specializations
  set verified = false,
      skill_level = null
  where technician_id = p_technician_id
    and verified
    and device_type = any(public.specialization_devices(p_specialization));

  get diagnostics v_rows = row_count;

  perform public.evaluate_technician_badge(p_technician_id);

  return case when v_rows > 0 then 'skill_deverified'
              else 'not_verified_for_specialization' end;
end;
$function$;

revoke all on function public.apply_dispute_deverification(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.apply_dispute_deverification(uuid, text, uuid) to service_role;

-- Re-created with the finding and remedy. Dropped first so the old
-- four-argument signature does not linger as an ambiguous overload.
drop function if exists public.resolve_job_dispute(uuid, text, text, uuid);

create function public.resolve_job_dispute(
  p_dispute_id uuid,
  p_decision   text,
  p_note       text,
  p_admin_id   uuid,
  p_outcome    text default null,
  p_remedy     text default 'none',
  p_remedy_specialization text default null
)
returns public.job_disputes
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_row public.job_disputes%rowtype;
  v_outcome text;
  v_remedy text := coalesce(p_remedy, 'none');
  v_tech uuid;
begin
  if p_decision not in ('resolved', 'dismissed') then
    raise exception 'A decision is either resolved or dismissed.';
  end if;

  if length(trim(coalesce(p_note, ''))) < 5 then
    raise exception 'Write the decision out - both sides are shown it word for word.';
  end if;

  if not exists (
    select 1 from public.profiles where id = p_admin_id and role = 'admin'
  ) then
    raise exception 'Only an admin can decide a report.';
  end if;

  select * into v_row
  from public.job_disputes
  where id = p_dispute_id and status = 'open'
  for update;

  if not found then
    raise exception 'That report was not found, or has already been decided.';
  end if;

  -- "Close without action" is never upheld. "Mark resolved" is upheld unless
  -- the admin says otherwise (e.g. sorted out, nobody at fault).
  v_outcome := case when p_decision = 'dismissed' then 'not_upheld'
                    else coalesce(p_outcome, 'upheld') end;

  if v_outcome not in ('upheld', 'not_upheld') then
    raise exception 'The finding is either upheld or not upheld.';
  end if;

  if v_remedy not in ('none', 'skill_deverification') then
    raise exception 'Unknown remedy: %', v_remedy;
  end if;

  if v_remedy = 'skill_deverification' then
    if p_decision <> 'resolved' or v_outcome <> 'upheld'
       or v_row.raised_by_role <> 'client' then
      raise exception 'Skill de-verification needs an upheld report raised by the client.';
    end if;

    if p_remedy_specialization is null
       or cardinality(public.specialization_devices(p_remedy_specialization)) = 0 then
      raise exception 'Choose which specialisation the de-verification removes.';
    end if;

    select assigned_technician_id into v_tech
    from public.jobs where id = v_row.job_id;

    if v_tech is null then
      raise exception 'This job has no technician to de-verify.';
    end if;

    -- Before the finding is written, and judged without this report - see
    -- apply_dispute_deverification.
    perform public.apply_dispute_deverification(
      v_tech, p_remedy_specialization, p_dispute_id
    );
  end if;

  update public.job_disputes
  set status = p_decision,
      outcome = v_outcome,
      remedy = v_remedy,
      remedy_specialization = case when v_remedy = 'skill_deverification'
                                   then p_remedy_specialization end,
      resolution_note = trim(p_note),
      resolved_by = p_admin_id,
      resolved_at = now()
  where id = p_dispute_id
  returning * into v_row;

  return v_row;
end;
$function$;

revoke all on function public.resolve_job_dispute(uuid, text, text, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.resolve_job_dispute(uuid, text, text, uuid, text, text, text)
  to service_role;


-- ---------------------------------------------------------------------------
-- 9. The guard lets the evaluator through
-- ---------------------------------------------------------------------------
--
-- Copied from 20260907000003; only the badge check changed (NEW). A
-- technician still cannot write their own badge: the flag is set only inside
-- evaluate_technician_badge(), within the same transaction, and PostgREST
-- gives a client no way to call set_config.

create or replace function public.guard_technician_self_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if auth.uid() is null or auth.uid() <> new.id then
    return new;
  end if;

  if new.is_verified is distinct from old.is_verified then
    raise exception 'A technician cannot change their own verification status';
  end if;

  if new.tier is distinct from old.tier then
    raise exception 'A technician cannot change their own tier';
  end if;

  if new.verification_tier is distinct from old.verification_tier then
    raise exception 'A technician cannot change their own verification tier';
  end if;

  -- NEW: unless the change is the badge evaluator's.
  if new.badge is distinct from old.badge
     and coalesce(current_setting('sugo.badge_eval', true), '') <> 'on'
  then
    raise exception 'A technician cannot change their own badge';
  end if;

  if new.rating is distinct from old.rating then
    raise exception 'Rating is computed from job outcomes, not set by hand';
  end if;

  if new.total_jobs is distinct from old.total_jobs then
    raise exception 'Job count is computed from job outcomes, not set by hand';
  end if;

  if new.current_workload is distinct from old.current_workload then
    raise exception 'Workload is maintained by the booking flow';
  end if;

  return new;
end;
$function$;


-- ---------------------------------------------------------------------------
-- 10. When to recompute: the events
-- ---------------------------------------------------------------------------
--
--   job completion            jobs.status, job_outcomes insert
--   a new or changed rating   job_outcomes.final_rating (synced from reviews)
--   a dispute status change   job_disputes insert / update
--   an offer answered/missed  job_matches leaving 'offered'
--   competency approved/lost  technician_specializations.verified
--   identity decision         identity_verifications.status
-- A cancellation would be a jobs.status change, already covered.

create or replace function public.trust_badge_after_outcome()
returns trigger language plpgsql security definer set search_path = public
as $function$
begin
  if tg_op = 'DELETE' then
    perform public.evaluate_technician_badge(old.technician_id);
  else
    perform public.evaluate_technician_badge(new.technician_id);
  end if;
  return null;
end;
$function$;

drop trigger if exists trust_badge_after_outcome on public.job_outcomes;
create trigger trust_badge_after_outcome
  after insert or update of final_rating or delete on public.job_outcomes
  for each row execute function public.trust_badge_after_outcome();

create or replace function public.trust_badge_after_job()
returns trigger language plpgsql security definer set search_path = public
as $function$
begin
  perform public.evaluate_technician_badge(new.assigned_technician_id);
  if old.assigned_technician_id is distinct from new.assigned_technician_id then
    perform public.evaluate_technician_badge(old.assigned_technician_id);
  end if;
  return null;
end;
$function$;

drop trigger if exists trust_badge_after_job on public.jobs;
create trigger trust_badge_after_job
  after update of status, assigned_technician_id on public.jobs
  for each row
  when (old.status is distinct from new.status
        or old.assigned_technician_id is distinct from new.assigned_technician_id)
  execute function public.trust_badge_after_job();

create or replace function public.trust_badge_after_offer()
returns trigger language plpgsql security definer set search_path = public
as $function$
begin
  perform public.evaluate_technician_badge(old.technician_id);
  return null;
end;
$function$;

-- Only when an offer is answered, withdrawn or cleared - not on every
-- shortlist the engine writes and deletes.
drop trigger if exists trust_badge_after_offer on public.job_matches;
create trigger trust_badge_after_offer
  after update of status or delete on public.job_matches
  for each row
  when (old.status = 'offered')
  execute function public.trust_badge_after_offer();

create or replace function public.trust_badge_after_dispute()
returns trigger language plpgsql security definer set search_path = public
as $function$
begin
  perform public.evaluate_technician_badge(
    (select assigned_technician_id from public.jobs where id = new.job_id)
  );
  return null;
end;
$function$;

drop trigger if exists trust_badge_after_dispute on public.job_disputes;
create trigger trust_badge_after_dispute
  after insert or update on public.job_disputes
  for each row execute function public.trust_badge_after_dispute();

create or replace function public.trust_badge_after_specialization()
returns trigger language plpgsql security definer set search_path = public
as $function$
begin
  if tg_op = 'DELETE' then
    perform public.evaluate_technician_badge(old.technician_id);
  else
    perform public.evaluate_technician_badge(new.technician_id);
  end if;
  return null;
end;
$function$;

drop trigger if exists trust_badge_after_specialization on public.technician_specializations;
create trigger trust_badge_after_specialization
  after insert or update of verified, device_type or delete
  on public.technician_specializations
  for each row execute function public.trust_badge_after_specialization();

create or replace function public.trust_badge_after_identity()
returns trigger language plpgsql security definer set search_path = public
as $function$
begin
  perform public.evaluate_technician_badge(new.user_id);
  return null;
end;
$function$;

drop trigger if exists trust_badge_after_identity on public.identity_verifications;
create trigger trust_badge_after_identity
  after insert or update of status on public.identity_verifications
  for each row execute function public.trust_badge_after_identity();


-- ---------------------------------------------------------------------------
-- 11. Backfill, then constrain the column
-- ---------------------------------------------------------------------------
--
-- Every technician gets their computed level, replacing whatever free text
-- `badge` held. Only then can the column be held to the three values.

select public.evaluate_all_technician_badges();

alter table public.technicians drop constraint if exists technicians_badge_level;
alter table public.technicians add constraint technicians_badge_level
  check (badge is null or badge in ('id_verified', 'skill_verified', 'community_trusted'));

comment on column public.technicians.badge is
  'Progressive Trust Badge: id_verified < skill_verified < community_trusted, '
  'or null below the baseline. Written only by evaluate_technician_badge().';


-- ---------------------------------------------------------------------------
-- 12. The client preference ladder uses the same badge
-- ---------------------------------------------------------------------------
--
-- 20261115000001 topped the ladder with certified_pro, chosen because no
-- track-record signal existed then. Community Trusted is that signal.

alter table public.jobs drop constraint if exists jobs_pref_min_trust_check;

update public.jobs
set pref_min_trust = 'community_trusted'
where pref_min_trust = 'certified_pro';

alter table public.jobs add constraint jobs_pref_min_trust_check
  check (pref_min_trust in ('id_verified', 'skill_verified', 'community_trusted'));

comment on column public.jobs.pref_min_trust is
  'Client preference (hard gate, ordered): id_verified < skill_verified < '
  'community_trusted. Null = no preference.';


-- ---------------------------------------------------------------------------
-- 13. Nightly re-check
-- ---------------------------------------------------------------------------
--
-- 18:00 UTC is 02:00 in Manila. Catches offers that crossed the 24 h window
-- with no event, and anything an event missed. Skipped where pg_cron is not
-- installed (it is on the hosted project, since 20260916000005).

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('sugo-trust-badge-nightly');
    exception
      when others then null;  -- not scheduled yet, the normal first run
    end;

    perform cron.schedule(
      'sugo-trust-badge-nightly',
      '0 18 * * *',
      'select public.evaluate_all_technician_badges()'
    );
  end if;
end
$$;
