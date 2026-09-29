-- SUGO: live tracking for the pickup and delivery legs
--
-- When a technician reroutes a job to the shop, the appliance makes two trips
-- it did not make before: to the shop, and back again after the repair. The
-- client is handing over their property and then waiting on it, so both legs
-- need to be visible on a map rather than taken on trust.
--
-- This is the tracking module the `TODO(tracking)` markers in
-- `job-response/index.ts` and `active_job_card.dart` pointed at.

-- ---------------------------------------------------------------------------
-- 1. One tracking row per job
-- ---------------------------------------------------------------------------
--
-- `unique (job_id)` on purpose: this is the *current* position and stage, not
-- a location history. A breadcrumb trail would grow without bound for no gain
-- - the client wants to know where the van is now, not where it was at 14:02.
--
-- Coordinates are nullable because a stage can be active before the first
-- position arrives (the technician has not granted location permission yet, or
-- is indoors with no fix).

create table if not exists public.job_tracking (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references public.jobs(id) on delete cascade not null unique,
  technician_id uuid references public.technicians(id) on delete cascade not null,
  stage text not null default 'heading_to_pickup' check (stage in (
    'heading_to_pickup',   -- on the way to collect the unit
    'collected',           -- unit in hand, heading back
    'returning_to_shop',
    'in_repair',           -- at the bench; no travel, so no map
    'out_for_delivery',    -- repaired, on the way back to the client
    'delivered'
  )),
  latitude double precision,
  longitude double precision,
  -- Metres of GPS uncertainty, so the map can size the accuracy halo honestly
  -- instead of drawing a confident dot over a 200 m guess.
  accuracy_m double precision,
  heading double precision,
  note text,
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_job_tracking_technician
  on public.job_tracking (technician_id);

create index if not exists idx_job_tracking_stage
  on public.job_tracking (stage);

comment on table public.job_tracking is
  'Current position and stage for a job that involves transport. One row per '
  'job - the live position, not a history trail.';

-- Keep updated_at honest without the client having to send it.
create or replace function public.touch_job_tracking()
returns trigger
language plpgsql
as $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

drop trigger if exists job_tracking_touch on public.job_tracking;
create trigger job_tracking_touch
  before update on public.job_tracking
  for each row execute function public.touch_job_tracking();

-- ---------------------------------------------------------------------------
-- 2. Row level security
-- ---------------------------------------------------------------------------

alter table public.job_tracking enable row level security;

-- The client watching their own appliance travel.
drop policy if exists "job_tracking_client_select" on public.job_tracking;
create policy "job_tracking_client_select"
  on public.job_tracking for select
  using (
    job_id in (select id from public.jobs where client_id = auth.uid())
  );

-- The technician doing the driving.
drop policy if exists "job_tracking_technician_select" on public.job_tracking;
create policy "job_tracking_technician_select"
  on public.job_tracking for select
  using (technician_id = auth.uid());

-- Only the assigned technician writes positions, and only for a job that is
-- actually theirs. The subquery is the load-bearing part: without it a
-- technician could post coordinates onto somebody else's job.
drop policy if exists "job_tracking_technician_insert" on public.job_tracking;
create policy "job_tracking_technician_insert"
  on public.job_tracking for insert to authenticated
  with check (
    technician_id = auth.uid()
    and job_id in (
      select id from public.jobs where assigned_technician_id = auth.uid()
    )
  );

drop policy if exists "job_tracking_technician_update" on public.job_tracking;
create policy "job_tracking_technician_update"
  on public.job_tracking for update to authenticated
  using (technician_id = auth.uid())
  with check (
    technician_id = auth.uid()
    and job_id in (
      select id from public.jobs where assigned_technician_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 3. Realtime
-- ---------------------------------------------------------------------------
--
-- Added to the `supabase_realtime` publication so the client's map updates as
-- the technician moves, instead of polling every few seconds and draining both
-- batteries.
--
-- `replica identity full` makes the old row available on updates, which is what
-- lets a subscriber diff a position change rather than only seeing the new
-- value. Realtime still applies RLS per subscriber, so a client only ever
-- receives rows for their own jobs.

alter table public.job_tracking replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'job_tracking'
  ) then
    alter publication supabase_realtime add table public.job_tracking;
  end if;
exception
  when undefined_object then
    -- No realtime publication on this project; the app falls back to polling.
    raise notice 'supabase_realtime publication not found, skipping';
end $$;

-- ---------------------------------------------------------------------------
-- 4. Shop location on the technician
-- ---------------------------------------------------------------------------
--
-- A pickup job travels to *the shop*, which is not the same as the
-- technician's current position. Without a fixed destination the map can show
-- where the van is but not where it is going, which is half a tracking screen.

alter table public.technicians
  add column if not exists shop_latitude double precision;

alter table public.technicians
  add column if not exists shop_longitude double precision;

alter table public.technicians
  add column if not exists shop_name text;

comment on column public.technicians.shop_latitude is
  'Where a picked-up unit is taken for repair. Falls back to the technician''s '
  'own latitude/longitude when not set.';
