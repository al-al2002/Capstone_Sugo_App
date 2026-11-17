-- SUGO: two more moments that reach a phone with the app closed (2026-11-17)
--
-- At the user's request ("notification all updates on task and also the
-- arrival on technician client when the phone is closed the app"). Pushes
-- already went out for a new request, messages, every tracking stage, delays,
-- the client setting off and a completed job. Two moments still reached
-- nobody, because they happen inside a database function rather than in an
-- edge function:
--
--   1. The client cancels a request a technician was waiting to answer
--      (`withdraw_technician_offer`). The technician kept seeing a request
--      that was gone until they opened the app.
--   2. The client arrives at the shop - to drop the unit off or collect it
--      (`end_collection_trip`). The technician waiting at the bench was not
--      told.
--
-- Each function is redefined with one `push_event()` call added - the same
-- hand-off every other push uses (20260922000006): ids only, `notify-event`
-- writes the words. No table, column or policy changes; a failed push never
-- fails the call (`push_event` swallows its own errors).

-- ---------------------------------------------------------------------------
-- 1. "Cancel request" tells the technician
-- ---------------------------------------------------------------------------
--
-- Copied from 20261117000004; only the push is new.

create or replace function public.withdraw_technician_offer(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_job     record;
  v_match   record;
begin
  select id, client_id, status
    into v_job
  from public.jobs
  where id = p_job_id;

  if v_job.id is null then
    raise exception 'Job not found' using errcode = 'P0002';
  end if;

  if v_job.client_id <> auth.uid() then
    raise exception 'This job belongs to someone else' using errcode = '42501';
  end if;

  if v_job.status in ('confirmed', 'in_progress', 'completed', 'cancelled') then
    raise exception 'This job has already been %', v_job.status
      using errcode = '22023';
  end if;

  select id, technician_id
    into v_match
  from public.job_matches
  where job_id = p_job_id and status = 'offered'
  limit 1;

  if v_match.id is null then
    raise exception 'There is no request waiting on this job'
      using errcode = 'P0002';
  end if;

  update public.job_matches
  set status = 'shortlisted'
  where id = v_match.id;

  -- 2026-11-17: a booked technician was cancelled on.
  insert into public.booking_cancellations
    (client_id, job_id, technician_id, kind)
  values
    (v_job.client_id, p_job_id, v_match.technician_id, 'withdraw');

  -- NEW: tell the technician the request is gone.
  perform public.push_event(
    jsonb_build_object(
      'type', 'withdrawn',
      'job_id', p_job_id,
      'technician_id', v_match.technician_id
    )
  );

  return jsonb_build_object(
    'job_id', p_job_id,
    'match_id', v_match.id,
    'technician_id', v_match.technician_id,
    'status', 'withdrawn',
    'booking_paused_until', public.booking_cooldown_until(v_job.client_id)
  );
end;
$function$;

revoke all on function public.withdraw_technician_offer(uuid) from public;
revoke all on function public.withdraw_technician_offer(uuid) from anon;
grant execute on function public.withdraw_technician_offer(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. "I've arrived" tells the technician
-- ---------------------------------------------------------------------------
--
-- Copied from 20261117000006; the push and the two lines that make it fire
-- once are new.

create or replace function public.end_collection_trip(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_stage text;
  v_already timestamptz;
begin
  -- NEW: was this arrival already announced? Tapping twice must not tell
  -- the technician twice.
  select t.client_arrived_at into v_already
  from public.job_tracking t
  where t.job_id = p_job_id;

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
    and t.client_trip_started_at is not null
  returning t.stage into v_stage;

  if not found then
    raise exception 'There is no trip to end for this job'
      using errcode = '42501';
  end if;

  -- NEW: the technician waiting at the shop is told. The stage lets the push
  -- say "with the unit" or "to collect it".
  if v_already is null then
    perform public.push_event(
      jsonb_build_object(
        'type', 'arrived',
        'job_id', p_job_id,
        'stage', v_stage
      )
    );
  end if;
end;
$function$;

revoke all on function public.end_collection_trip(uuid) from public, anon;
grant execute on function public.end_collection_trip(uuid) to authenticated;
