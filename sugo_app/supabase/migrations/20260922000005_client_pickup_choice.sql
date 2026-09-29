-- =============================================================================
-- "I'll pick it up myself": the client chooses how a repaired unit comes back
-- =============================================================================
--
-- A pickup job - booked as shop pickup, or a home visit that turned into one
-- ("needs shop") - ends with the unit at the workshop. Since 20260916000007 it
-- can leave two ways: the technician delivers it, or the client collects it.
-- But the TECHNICIAN chose, at the bench, and the client found out afterwards.
--
-- This lets the client say it first. Choosing "I'll pick it up myself":
--
--   * tells the technician, on their Jobs list and delivery screen, that there
--     is no delivery trip to make;
--   * stops `out_for_delivery` being recorded for the job (trigger below), so
--     the two cannot end up disagreeing about where the unit is going;
--   * opens the client's in-app route to the workshop straight away, rather
--     than only once the unit is ready - they can see where they are going
--     and plan the trip.
--
-- WHY A TABLE OF ITS OWN, NOT A COLUMN ON job_tracking
--
--   1. `job_tracking` is the technician's row. Only they write it (its update
--      policy), and every write bumps `updated_at`, which the client screen
--      reads as the freshness of the live position. A client choice stored
--      there would make a stale GPS dot read as "Live".
--   2. The tracking row only exists once the technician starts moving. The
--      client should be able to choose as soon as the job is booked.
--
-- Nothing here touches the four frozen RB-CARS tables.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. The choice
-- ---------------------------------------------------------------------------

create table if not exists public.job_return_preferences (
  job_id uuid primary key references public.jobs(id) on delete cascade,
  method text not null check (method in ('delivery', 'client_pickup')),
  chosen_at timestamptz not null default now()
);

comment on table public.job_return_preferences is
  'How the client wants a repaired pickup job back: delivered by the '
  'technician, or collected by the client at the workshop. No row means '
  'delivery, the default. Written only through set_return_method().';

alter table public.job_return_preferences enable row level security;

-- Both parties to the job may read it; nobody writes it directly.
drop policy if exists "return_pref_select_parties" on public.job_return_preferences;
create policy "return_pref_select_parties"
  on public.job_return_preferences for select to authenticated
  using (
    exists (
      select 1 from public.jobs j
      where j.id = job_id
        and (j.client_id = auth.uid() or j.assigned_technician_id = auth.uid())
    )
  );

revoke all on public.job_return_preferences from anon;
grant select on public.job_return_preferences to authenticated;


-- ---------------------------------------------------------------------------
-- 2. Choosing - the only way in
-- ---------------------------------------------------------------------------
--
-- SECURITY DEFINER with the rules checked by hand, because the table has no
-- write policy. The rules:
--
--   * only the client who posted the job;
--   * only a pickup job, and only once a technician has it (confirmed or in
--     progress) - before that there is nobody to tell;
--   * not once the unit is out for delivery or delivered - the trip is
--     already happening, or over;
--   * switching back to delivery is refused once the unit is waiting at the
--     shop: `ready_for_collection` has no route to `out_for_delivery`, so the
--     change has to be agreed with the technician in chat.

create or replace function public.set_return_method(p_job_id uuid, p_method text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_job record;
  v_stage text;
begin
  if p_method not in ('delivery', 'client_pickup') then
    raise exception 'Choose delivery or pickup' using errcode = '22023';
  end if;

  select id, client_id, service_path, status into v_job
  from public.jobs where id = p_job_id;

  if v_job.id is null then
    raise exception 'Job not found' using errcode = 'P0002';
  end if;
  if v_job.client_id is distinct from auth.uid() then
    raise exception 'This job belongs to someone else' using errcode = '42501';
  end if;
  if v_job.service_path is distinct from 'pickup' then
    raise exception 'Only a workshop repair can be picked up' using errcode = '23514';
  end if;
  if v_job.status not in ('confirmed', 'in_progress') then
    raise exception 'This can be chosen once a technician has the job'
      using errcode = '23514';
  end if;

  select stage into v_stage from public.job_tracking where job_id = p_job_id;

  if v_stage in ('out_for_delivery', 'delivered') then
    raise exception 'It is already on its way back to you' using errcode = '23514';
  end if;
  if p_method = 'delivery' and v_stage = 'ready_for_collection' then
    raise exception 'It is already waiting at the shop. Message the technician to arrange a delivery.'
      using errcode = '23514';
  end if;

  insert into public.job_return_preferences (job_id, method, chosen_at)
  values (p_job_id, p_method, now())
  on conflict (job_id) do update
    set method = excluded.method, chosen_at = excluded.chosen_at;

  return jsonb_build_object('job_id', p_job_id, 'method', p_method, 'stage', v_stage);
end;
$function$;

comment on function public.set_return_method(uuid, text) is
  'The client choosing delivery or collecting a repaired pickup job themselves.';

revoke all on function public.set_return_method(uuid, text) from public, anon;
grant execute on function public.set_return_method(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 3. The technician cannot deliver what the client is collecting
-- ---------------------------------------------------------------------------
--
-- The technician's screen hides "Out for delivery" once the client has chosen
-- to collect. This is the same rule where it cannot be skipped: an older
-- build, or a direct write, still cannot record a delivery the client said
-- they did not want. Only the transition INTO out_for_delivery is checked, so
-- a job already under way is never blocked mid-trip.

create or replace function public.job_tracking_respect_pickup()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.stage = 'out_for_delivery'
     and new.stage is distinct from old.stage
     and exists (
       select 1 from public.job_return_preferences p
       where p.job_id = new.job_id and p.method = 'client_pickup'
     )
  then
    raise exception 'The client is picking this up at your shop. Mark it ready for collection instead.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

drop trigger if exists job_tracking_respect_pickup on public.job_tracking;
create trigger job_tracking_respect_pickup
  before update on public.job_tracking
  for each row execute function public.job_tracking_respect_pickup();
