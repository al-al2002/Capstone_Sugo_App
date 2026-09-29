-- SUGO: automatic delay detection on a tracking leg
--
-- The client could already see rain and traffic, but nothing ever told them
-- their technician was running late - they had to open the tracking screen and
-- work it out themselves. This adds the state that lets the system say it.
--
-- ## The model
--
-- When a leg starts, the first ETA becomes a PROMISE: `expected_arrival_at`.
-- It is written once and never moves. Every later sample writes
-- `projected_arrival_at`, and the gap between the two is the delay.
--
-- Freezing the baseline is the whole design. An ETA that quietly slides forward
-- as traffic worsens always says "arriving in 10 minutes" and is therefore
-- never late - which is exactly how delivery apps lose people's trust. Keeping
-- the original promise is what makes lateness measurable at all.
--
-- ## Why no new table
--
-- `job_tracking` is already one row per job holding the current state of the
-- leg, and this is more current state of the same leg. A second table would
-- need the same key, the same RLS and a join on every read.
--
-- ## What computes these
--
-- Not the database. An ETA needs live traffic from TomTom, which a trigger
-- cannot fetch. The `tracking-eta` edge function samples it on the service role
-- and writes these columns; Postgres's job here is to hold the values, reset
-- them when the leg changes, and stop anyone else writing them.

-- ---------------------------------------------------------------------------
-- 1. The columns
-- ---------------------------------------------------------------------------

alter table public.job_tracking
  add column if not exists expected_arrival_at timestamptz;

comment on column public.job_tracking.expected_arrival_at is
  'The promise: arrival as first estimated when this leg began. Written once '
  'per leg and never revised - revising it would make lateness undetectable.';

alter table public.job_tracking
  add column if not exists projected_arrival_at timestamptz;

comment on column public.job_tracking.projected_arrival_at is
  'Arrival as currently estimated. Rewritten on every ETA sample.';

alter table public.job_tracking
  add column if not exists delay_minutes numeric(6,1);

comment on column public.job_tracking.delay_minutes is
  'projected_arrival_at - expected_arrival_at, in minutes. Zero or negative '
  'means on time or early. Stored rather than derived so the app can filter '
  'and display it without recomputing.';

-- Null when not delayed, or when we could not attribute it. Attribution is a
-- claim about the world and is only made when the sampled data supports it:
-- see `tracking-eta` for the thresholds.
alter table public.job_tracking
  add column if not exists delay_reason text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'job_tracking_delay_reason_check'
  ) then
    alter table public.job_tracking
      add constraint job_tracking_delay_reason_check
      check (delay_reason is null or delay_reason in ('traffic', 'weather', 'both'));
  end if;
end
$$;

alter table public.job_tracking
  add column if not exists eta_sampled_at timestamptz;

comment on column public.job_tracking.eta_sampled_at is
  'When the ETA was last recomputed. The app throttles on this so a moving '
  'vehicle does not call TomTom on every GPS fix.';

-- Set when the client has been told. Exists so a delay is announced once
-- rather than on every sample for the rest of the journey - the difference
-- between a notification and a pestering.
alter table public.job_tracking
  add column if not exists delay_notified_at timestamptz;

-- ---------------------------------------------------------------------------
-- 2. One trigger: protect the columns, and invalidate them on a new leg
-- ---------------------------------------------------------------------------
--
-- Two rules have to hold on every UPDATE, and the order between them matters:
--
--   A. Only the server may set these figures. `job_tracking_technician_update`
--      lets the assigned technician update their own row - correct, because
--      that is how positions arrive - but RLS filters ROWS, not COLUMNS, so
--      that policy alone would let a technician's session write
--      `delay_minutes = 0` and erase their own lateness.
--
--   B. A stage change invalidates the leg. The destination flips when the
--      stage reaches `out_for_delivery`: the unit stops heading to the
--      workshop and starts heading back to the client, so every figure below
--      describes a journey that is over. Without clearing them the client
--      would be told the delivery was 40 minutes late because the *pickup*
--      ran long.
--
-- WHY ONE TRIGGER AND NOT TWO. Postgres fires BEFORE triggers in name order,
-- so as two functions the guard would run second and copy OLD back over the
-- nulls the reset had just written - a technician advancing the stage would
-- silently keep the previous leg's baseline and be measured against the wrong
-- promise. Doing both here makes the precedence explicit instead of dependent
-- on what the triggers happen to be called: restore first, then invalidate.
--
-- `auth.uid()` is null for the service role, edge functions and pg_cron, which
-- is the same test 20260905000002 uses to protect the `technicians` counters.
--
-- Silently restoring rather than raising is deliberate: `pushPosition` runs on
-- a moving vehicle several times a minute and swallows its errors, so an
-- exception here would be invisible to everyone while quietly dropping
-- positions.

create or replace function public.guard_tracking_eta_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  -- A. A real user session may not move these. The service role may.
  if auth.uid() is not null then
    new.expected_arrival_at := old.expected_arrival_at;
    new.projected_arrival_at := old.projected_arrival_at;
    new.delay_minutes := old.delay_minutes;
    new.delay_reason := old.delay_reason;
    new.eta_sampled_at := old.eta_sampled_at;
    new.delay_notified_at := old.delay_notified_at;
  end if;

  -- B. A new leg is a new promise. Applied after the restore, so a technician
  -- advancing the stage still clears the old leg even though they could not
  -- have written these values themselves.
  if new.stage is distinct from old.stage then
    new.expected_arrival_at := null;
    new.projected_arrival_at := null;
    new.delay_minutes := null;
    new.delay_reason := null;
    new.eta_sampled_at := null;
    new.delay_notified_at := null;
  end if;

  return new;
end;
$function$;

drop trigger if exists job_tracking_reset_eta on public.job_tracking;
drop trigger if exists job_tracking_zguard_eta on public.job_tracking;

drop trigger if exists job_tracking_guard_eta on public.job_tracking;
create trigger job_tracking_guard_eta
  before update on public.job_tracking
  for each row execute function public.guard_tracking_eta_columns();
