-- SUGO: the client's trip to the workshop, tracked like the technician's
--
-- A client who chose to collect their repaired unit (`ready_for_collection`)
-- used to make that trip unseen: "the client's own trip, which SUGO neither
-- tracks nor estimates". The technician waiting at the shop had no idea
-- whether they were five minutes out or had forgotten. This lets the client
-- share their position for that one trip, and runs it through the same ETA
-- and delay machinery as every other leg - so the technician gets "your client
-- is running late" for rain or traffic, the mirror of what the client gets.
--
-- Approved by the user on 2026-09-29 ("columns on job_tracking").
--
-- ## Why columns, not a table
--
-- `job_tracking` is one row per job holding the current state of the current
-- leg, and this is the current leg. The ETA columns (`expected_arrival_at`,
-- `delay_minutes`, ...) are per leg and already mean exactly the right thing;
-- only the traveller is different. A second table would need its own RLS, its
-- own realtime channel and a join on every read, for one leg of one path.
--
-- The client's position gets its own columns rather than reusing `latitude` /
-- `longitude`, which are the technician's. Sharing one pair would let either
-- party overwrite the other, and would make "whose dot is this?" depend on the
-- stage - an easy thing to get wrong on a map.
--
-- ## Why functions, and no new policy
--
-- RLS is not loosened. The client still cannot UPDATE `job_tracking`; they
-- reach these columns only through the three functions below, which check
-- that the caller is the job's client and that the unit is actually waiting
-- to be collected. A policy could not say that: RLS filters rows, not
-- columns, and an update policy for the client would let them rewrite the
-- stage, the technician's position and the delay figures too.
--
-- ## Privacy
--
-- The client's position exists only while they are travelling. Arriving
-- clears it, and so does any stage change (the guard trigger below). Nothing
-- keeps a history; like the technician's, it is one current point.

-- ---------------------------------------------------------------------------
-- 1. The columns
-- ---------------------------------------------------------------------------

alter table public.job_tracking
  add column if not exists client_latitude double precision,
  add column if not exists client_longitude double precision,
  add column if not exists client_accuracy_m double precision,
  add column if not exists client_position_at timestamptz,
  add column if not exists client_trip_started_at timestamptz,
  add column if not exists client_arrived_at timestamptz;

comment on column public.job_tracking.client_trip_started_at is
  'When the client set off to collect the unit (ready_for_collection only). '
  'Null while they have not.';
comment on column public.job_tracking.client_arrived_at is
  'When the client said they had arrived at the workshop. Ends the trip: no '
  'ETA is sampled and no delay reported after it.';
comment on column public.job_tracking.client_latitude is
  'The client''s current position during their collection trip, and only then. '
  'Cleared on arrival and on any stage change.';

-- ---------------------------------------------------------------------------
-- 2. The guard, extended
-- ---------------------------------------------------------------------------
--
-- Same two rules as 20260916000003, now covering the client's columns too:
--
--   A. A direct write from the app may not move the server-owned columns.
--      The technician's update policy lets them write their own row, and RLS
--      cannot stop them writing `client_latitude` or `delay_minutes = 0`, so
--      the trigger puts those back.
--   B. A stage change starts a new leg: the old ETA is void, and the client's
--      trip (if any) is over.
--
-- ONE CHANGE TO RULE A. It used to test `auth.uid() is not null`. That is also
-- true inside the functions below, which run for the client, so they could not
-- have written anything. It now tests the ROLE the statement runs as: a direct
-- write from the app runs as `authenticated`; a SECURITY DEFINER function runs
-- as its owner; edge functions run as `service_role`; pg_cron as `postgres`.
-- For that to work this trigger function must itself be SECURITY INVOKER -
-- a definer trigger would always see its own owner. It only rewrites NEW, so
-- it needs no privileges of its own.
create or replace function public.guard_tracking_eta_columns()
returns trigger
language plpgsql
security invoker
set search_path = public
as $function$
begin
  -- A. Straight from the app: the server's columns stay as they were.
  if current_user in ('authenticated', 'anon') then
    new.expected_arrival_at := old.expected_arrival_at;
    new.projected_arrival_at := old.projected_arrival_at;
    new.delay_minutes := old.delay_minutes;
    new.delay_reason := old.delay_reason;
    new.eta_sampled_at := old.eta_sampled_at;
    new.delay_notified_at := old.delay_notified_at;
    new.client_latitude := old.client_latitude;
    new.client_longitude := old.client_longitude;
    new.client_accuracy_m := old.client_accuracy_m;
    new.client_position_at := old.client_position_at;
    new.client_trip_started_at := old.client_trip_started_at;
    new.client_arrived_at := old.client_arrived_at;
  end if;

  -- B. A new leg. After the restore, so a technician advancing the stage
  -- still clears the old leg although they could not write these themselves.
  if new.stage is distinct from old.stage then
    new.expected_arrival_at := null;
    new.projected_arrival_at := null;
    new.delay_minutes := null;
    new.delay_reason := null;
    new.eta_sampled_at := null;
    new.delay_notified_at := null;
    new.client_latitude := null;
    new.client_longitude := null;
    new.client_accuracy_m := null;
    new.client_position_at := null;
    new.client_trip_started_at := null;
    new.client_arrived_at := null;
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3. The client's three calls
-- ---------------------------------------------------------------------------

-- "I'm on my way." Opens the trip, starts a fresh promise, tells the
-- technician. Safe to call again after arriving or stopping: that is a new
-- trip, measured from scratch.
create or replace function public.start_collection_trip(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_client uuid;
  v_status text;
  v_stage text;
  v_started timestamptz;
  v_arrived timestamptz;
begin
  select j.client_id, j.status, t.stage, t.client_trip_started_at,
         t.client_arrived_at
    into v_client, v_status, v_stage, v_started, v_arrived
  from public.jobs j
  join public.job_tracking t on t.job_id = j.id
  where j.id = p_job_id;

  if not found then
    raise exception 'There is nothing to collect for this job'
      using errcode = 'P0002';
  end if;
  if v_client is distinct from auth.uid() then
    raise exception 'This job belongs to someone else' using errcode = '42501';
  end if;
  if v_stage <> 'ready_for_collection'
     or v_status not in ('confirmed', 'in_progress') then
    raise exception 'You can share your trip once it is ready for collection'
      using errcode = '23514';
  end if;

  update public.job_tracking
  set client_trip_started_at = now(),
      client_arrived_at = null,
      client_latitude = null,
      client_longitude = null,
      client_accuracy_m = null,
      client_position_at = null,
      expected_arrival_at = null,
      projected_arrival_at = null,
      delay_minutes = null,
      delay_reason = null,
      eta_sampled_at = null,
      delay_notified_at = null
  where job_id = p_job_id;

  -- Only for a trip that was not already under way, so tapping twice does
  -- not tell the technician twice.
  if v_started is null or v_arrived is not null then
    perform public.push_event(
      jsonb_build_object('type', 'collection', 'job_id', p_job_id)
    );
  end if;
end;
$function$;

-- One position fix. Called every few seconds while the client travels, so it
-- does one indexed update and nothing else.
create or replace function public.share_collection_position(
  p_job_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_m double precision default null
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90
     or p_longitude not between -180 and 180 then
    raise exception 'That is not a position' using errcode = '22023';
  end if;

  update public.job_tracking t
  set client_latitude = p_latitude,
      client_longitude = p_longitude,
      client_accuracy_m = p_accuracy_m,
      client_position_at = now()
  from public.jobs j
  where t.job_id = p_job_id
    and j.id = t.job_id
    and j.client_id = auth.uid()
    and t.stage = 'ready_for_collection'
    and t.client_trip_started_at is not null
    and t.client_arrived_at is null;

  if not found then
    raise exception 'Location sharing is not open for this job'
      using errcode = '42501';
  end if;
end;
$function$;

-- "I've arrived." Ends the trip: the position is dropped and any delay is
-- cleared, because a trip that is over cannot be late.
create or replace function public.end_collection_trip(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  update public.job_tracking t
  set client_arrived_at = now(),
      client_latitude = null,
      client_longitude = null,
      client_accuracy_m = null,
      client_position_at = null,
      projected_arrival_at = null,
      delay_minutes = null,
      delay_reason = null
  from public.jobs j
  where t.job_id = p_job_id
    and j.id = t.job_id
    and j.client_id = auth.uid()
    and t.stage = 'ready_for_collection'
    and t.client_trip_started_at is not null;

  if not found then
    raise exception 'There is no trip to end for this job'
      using errcode = '42501';
  end if;
end;
$function$;

revoke all on function public.start_collection_trip(uuid)
  from public, anon;
revoke all on function public.share_collection_position(
  uuid, double precision, double precision, double precision
) from public, anon;
revoke all on function public.end_collection_trip(uuid)
  from public, anon;

grant execute on function public.start_collection_trip(uuid) to authenticated;
grant execute on function public.share_collection_position(
  uuid, double precision, double precision, double precision
) to authenticated;
grant execute on function public.end_collection_trip(uuid) to authenticated;
