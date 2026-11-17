-- Book-and-cancel cooldown (2026-11-17). Approved by the user, including the
-- new table.
--
-- ## The problem
--
-- A client could book a technician, cancel, book again, cancel again, as
-- often as they liked. Every booking reaches a real person (on an urgent job,
-- a full-screen alert that buzzes their phone), and nothing remembered the
-- cancels: "Delete request" erases the job, and "Cancel request" puts the
-- offer back on the shortlist. So there was nothing to count.
--
-- ## The rule (the user's numbers)
--
--   * A CANCEL is "Cancel request" or "Delete request" while a technician has
--     been booked (`job_matches.status = 'offered'`) and has not answered.
--     Deleting a post nobody was booked on is not a cancel.
--   * Two or more cancels within a rolling hour pause booking for two minutes
--     after the latest one. Each further cancel in that hour starts a fresh
--     two minutes. An hour with fewer than two cancels pauses nothing.
--
-- ## Where it is enforced
--
-- In `job-response` `select`, the only way a booking is ever made, on the
-- server. The app shows the countdown, but cannot lift it. Reinstalling or
-- clearing the app's data changes nothing, because the record is here.
--
-- ## What is NOT changed
--
-- No frozen RB-CARS table changes. `jobs` and `job_matches` keep their
-- columns and their policies.

-- ------------------------------------------------------------------ the log

create table public.booking_cancellations (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid not null references public.profiles(id) on delete cascade,
  -- No foreign key: "Delete request" removes the job, and this row has to
  -- outlive it - it is the evidence of the cancel.
  job_id        uuid not null,
  -- The technician who was booked and then cancelled on.
  technician_id uuid references public.profiles(id) on delete set null,
  kind          text not null check (kind in ('withdraw', 'delete')),
  cancelled_at  timestamptz not null default now()
);

comment on table public.booking_cancellations is
  'One row per booking a client cancelled before the technician answered '
  '("Cancel request" = withdraw, "Delete request" = delete). Feeds the '
  'two-minute booking pause. Written only by withdraw_technician_offer and '
  'job-response; clients may read their own rows.';

-- The one question ever asked of it: "this client's cancels, newest first".
create index booking_cancellations_client_recent
  on public.booking_cancellations (client_id, cancelled_at desc);

alter table public.booking_cancellations enable row level security;

-- Read your own, so the app can explain a pause. No insert, update or delete
-- policy: a client must not be able to erase their own record. Writes come
-- from the SECURITY DEFINER function below and from job-response on the
-- service role.
create policy booking_cancellations_select_own
  on public.booking_cancellations
  for select
  to authenticated
  using (client_id = auth.uid());

-- The same pattern as job_disputes: nothing for anon, read-only for
-- authenticated (and the policy above narrows that to their own rows).
revoke all on table public.booking_cancellations from anon;
revoke all on table public.booking_cancellations from authenticated;
grant select on public.booking_cancellations to authenticated;

-- ------------------------------------------------------------- the rule

create or replace function public.booking_cooldown_until(p_client_id uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  -- The rule as named numbers, so it can be read and defended as written.
  c_window    constant interval := interval '1 hour';    -- rolling window
  c_threshold constant integer  := 2;                    -- cancels that pause
  c_pause     constant interval := interval '2 minutes'; -- from the latest

  v_recent integer;
  v_latest timestamptz;
begin
  -- A signed-in client may only ask about themselves. job-response runs on
  -- the service role, where auth.uid() is null, and may ask about anyone.
  if auth.uid() is not null and auth.uid() <> p_client_id then
    raise exception 'You can only check your own bookings'
      using errcode = '42501';
  end if;

  select count(*), max(cancelled_at)
    into v_recent, v_latest
  from public.booking_cancellations
  where client_id = p_client_id
    and cancelled_at > now() - c_window;

  if v_recent < c_threshold or v_latest + c_pause <= now() then
    return null;
  end if;
  return v_latest + c_pause;
end;
$function$;

comment on function public.booking_cooldown_until(uuid) is
  'When this client may book again, or null when they may book now. Paused '
  'for 2 minutes after the latest cancel once there are 2+ cancels in the '
  'last hour.';

revoke all on function public.booking_cooldown_until(uuid) from public;
revoke all on function public.booking_cooldown_until(uuid) from anon;
grant execute on function public.booking_cooldown_until(uuid) to authenticated;
grant execute on function public.booking_cooldown_until(uuid) to service_role;

-- ---------------------------------------------- "Cancel request" now counts

-- Unchanged from 20260921000003 except for two lines: the cancel is logged,
-- and the answer says whether booking is now paused, so the app can start
-- the countdown at once.
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
