-- SUGO: the client's DROP-OFF trip, tracked like their collection trip
--
-- A Shop Repair the client brings in themselves ("I'll bring it",
-- 20261116000001) had no tracking at all until the technician tapped "Unit
-- received": the client drove across town unseen, and the technician waiting
-- at the shop could not tell whether they were two minutes out or had
-- forgotten. The collection trip (20260929000001) already solves exactly this
-- for the way BACK - the client shares their position, the server estimates
-- their arrival against live traffic and weather, and the technician is told
-- if they run late. This points the same machinery at the way IN.
--
-- Approved by the user on 2026-11-17 ("Yes, new stage"): one new stage, the
-- three existing client-trip functions widened to it. No new table, no new
-- column, no RLS change.
--
-- ## The new stage: `dropping_off`
--
-- The client is bringing the unit to the technician's shop. It comes BEFORE
-- `in_repair`, and only on a drop-off job: nothing else ever writes it.
--
--   dropping_off -> in_repair -> ready_for_collection -> delivered
--
-- Why a stage rather than "a client trip with no stage": `job_tracking` is
-- one row per job holding the current leg, every reader (the ETA sampler, the
-- live route, both apps) decides who is travelling from the stage, and a
-- stage change is what already clears the client's position and the old
-- estimate (`guard_tracking_eta_columns`, rule B). "Unit received" moves the
-- row to `in_repair`, so the client's location is wiped the moment the unit
-- changes hands - the privacy rule of the collection trip, for free.
--
-- ## Who creates the row
--
-- On a drop-off nobody has a tracking row until the unit arrives (the
-- technician's screen deliberately does not create one - it would tell the
-- client "technician on the way" for a trip nobody is making). So
-- `start_collection_trip` creates it, at `dropping_off`, when the job's own
-- client taps "I'm on my way" on a confirmed self drop-off. The row is the
-- assigned technician's (`technician_id`), exactly as if they had created it,
-- so their existing update policy lets them move it on to `in_repair`.
--
-- Inserting fires the stage push with `dropping_off`; `notify-event` has no
-- words for it and sends nothing, which is right - the technician is told by
-- the `collection` event below, and the client did this themselves.

-- ---------------------------------------------------------------------------
-- 1. The stage
-- ---------------------------------------------------------------------------

alter table public.job_tracking
  drop constraint if exists job_tracking_stage_check;

alter table public.job_tracking
  add constraint job_tracking_stage_check
  check (stage in (
    'dropping_off',         -- the client is bringing it to the shop
    'heading_to_pickup',    -- on the way to collect the unit
    'collected',            -- unit in hand, heading back
    'returning_to_shop',
    'in_repair',            -- at the bench; no travel, so no map
    'out_for_delivery',     -- repaired, on the way back to the client
    'ready_for_collection', -- repaired, waiting for the client at the shop
    'delivered'             -- the client has it, by either route
  ));

comment on column public.job_tracking.stage is
  'Where the unit is. A drop-off starts at dropping_off (the client bringing '
  'it in) and goes straight to in_repair; a pickup starts at '
  'heading_to_pickup. After in_repair the flow branches: out_for_delivery '
  'when the technician brings it back, ready_for_collection when the client '
  'comes to the shop. Both end at delivered.';

-- ---------------------------------------------------------------------------
-- 2. The client's three calls, widened
-- ---------------------------------------------------------------------------

-- "I'm on my way." Opens the trip - creating the row for a drop-off - starts
-- a fresh promise, tells the technician. Safe to call again.
create or replace function public.start_collection_trip(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_client uuid;
  v_status text;
  v_path text;
  v_option text;
  v_technician uuid;
  v_stage text;
  v_started timestamptz;
  v_arrived timestamptz;
begin
  select j.client_id, j.status, j.service_path, j.delivery_option,
         j.assigned_technician_id
    into v_client, v_status, v_path, v_option, v_technician
  from public.jobs j
  where j.id = p_job_id;

  if not found then
    raise exception 'There is nothing to collect for this job'
      using errcode = 'P0002';
  end if;
  if v_client is distinct from auth.uid() then
    raise exception 'This job belongs to someone else' using errcode = '42501';
  end if;
  if v_status not in ('confirmed', 'in_progress') then
    raise exception 'You can share your trip once your booking is confirmed'
      using errcode = '23514';
  end if;

  select t.stage, t.client_trip_started_at, t.client_arrived_at
    into v_stage, v_started, v_arrived
  from public.job_tracking t
  where t.job_id = p_job_id;

  if not found then
    -- A drop-off the technician has accepted but not yet received: this trip
    -- IS the first leg. Anything else without a row has nothing to travel to.
    if v_path = 'pickup' and v_option = 'self' and v_technician is not null then
      insert into public.job_tracking (job_id, technician_id, stage)
      values (p_job_id, v_technician, 'dropping_off')
      -- Two taps racing: the second finds the first one's row.
      on conflict (job_id) do nothing;

      select t.stage, t.client_trip_started_at, t.client_arrived_at
        into v_stage, v_started, v_arrived
      from public.job_tracking t
      where t.job_id = p_job_id;
    else
      raise exception 'There is nothing to collect for this job'
        using errcode = 'P0002';
    end if;
  end if;

  if v_stage not in ('ready_for_collection', 'dropping_off') then
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
      delay_notified_at = null,
      traffic_label = null,
      traffic_congestion = null,
      weather_label = null,
      weather_severity = null
  where job_id = p_job_id;

  -- Only for a trip that was not already under way, so tapping twice does
  -- not tell the technician twice. The stage lets the push say "dropping
  -- off" or "collecting".
  if v_started is null or v_arrived is not null then
    perform public.push_event(
      jsonb_build_object(
        'type', 'collection',
        'job_id', p_job_id,
        'stage', v_stage
      )
    );
  end if;
end;
$function$;

-- One position fix, on either of the client's legs.
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
    and t.stage in ('ready_for_collection', 'dropping_off')
    and t.client_trip_started_at is not null
    and t.client_arrived_at is null;

  if not found then
    raise exception 'Location sharing is not open for this job'
      using errcode = '42501';
  end if;
end;
$function$;

-- "I've arrived." The position is dropped and any delay cleared.
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
    and t.stage in ('ready_for_collection', 'dropping_off')
    and t.client_trip_started_at is not null;

  if not found then
    raise exception 'There is no trip to end for this job'
      using errcode = '42501';
  end if;
end;
$function$;

-- `create or replace` keeps the grants of 20260929000001; restated so this
-- file stands on its own.
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
