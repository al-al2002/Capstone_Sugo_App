-- Trip conditions on job_tracking (2026-11-17). Approved by the user.
--
-- ## What this is for
--
-- The trip card on home-service and shop-pickup jobs, for both the client and
-- the technician: "Weather is good · Traffic is light · Arriving in about
-- 20 min".
--
-- ## Why columns here, and not a call from the app
--
-- `tracking-eta` (and its pg_cron sweep) ALREADY fetch traffic and weather
-- every ~90 seconds to work out the ETA and to blame a delay on "traffic" or
-- "weather" - and then threw the labels away. Keeping them costs no extra API
-- call, reaches both sides over Realtime, and - the real reason - means the
-- card and the delay pop-up come from the SAME sample. If the card asked the
-- weather service separately, it could say "traffic is light" while the
-- pop-up said "delayed by heavy traffic", because they read different
-- moments.
--
-- `job_tracking` is not one of the four frozen RB-CARS tables.

alter table public.job_tracking
  add column if not exists traffic_label text,
  add column if not exists traffic_congestion numeric(4,3),
  add column if not exists weather_label text,
  add column if not exists weather_severity numeric(4,3);

comment on column public.job_tracking.traffic_label is
  'Traffic at the leg''s destination at the last ETA sample, in the matcher''s '
  'words ("clear roads", "light traffic", "moderate traffic", "heavy '
  'traffic", "road closure nearby"). Null when TomTom was unavailable.';
comment on column public.job_tracking.traffic_congestion is
  '0..1 congestion behind traffic_label (1 = standstill).';
comment on column public.job_tracking.weather_label is
  'Weather at the leg''s destination at the last ETA sample ("clear '
  'weather", "light rain", ...). Null when OpenWeatherMap was unavailable.';
comment on column public.job_tracking.weather_severity is
  '0..1 severity behind weather_label, the same scale Stage 2 and the delay '
  'attribution use (0.4 and up counts as bad weather).';

alter table public.job_tracking
  drop constraint if exists job_tracking_traffic_congestion_check,
  add constraint job_tracking_traffic_congestion_check
    check (traffic_congestion is null or traffic_congestion between 0 and 1),
  drop constraint if exists job_tracking_weather_severity_check,
  add constraint job_tracking_weather_severity_check
    check (weather_severity is null or weather_severity between 0 and 1);

-- ------------------------------------------------- only the server writes

-- The update guard from 20260929000001, with the four new columns added to
-- both blocks: an app cannot write them (a technician must not be able to
-- report "clear roads" to cover a late arrival), and a new leg clears them so
-- the workshop's weather is never shown for the trip to the client's home.
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
    new.traffic_label := old.traffic_label;
    new.traffic_congestion := old.traffic_congestion;
    new.weather_label := old.weather_label;
    new.weather_severity := old.weather_severity;
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
    new.traffic_label := null;
    new.traffic_congestion := null;
    new.weather_label := null;
    new.weather_severity := null;
  end if;

  return new;
end;
$function$;

-- The guard above runs on UPDATE only, but the technician's app INSERTS the
-- row when a trip starts. So the new columns get their own insert guard: from
-- the app they always start empty, and only the sampler fills them.
create or replace function public.guard_tracking_conditions_insert()
returns trigger
language plpgsql
security invoker
set search_path = public
as $function$
begin
  if current_user in ('authenticated', 'anon') then
    new.traffic_label := null;
    new.traffic_congestion := null;
    new.weather_label := null;
    new.weather_severity := null;
  end if;
  return new;
end;
$function$;

drop trigger if exists job_tracking_guard_conditions_insert on public.job_tracking;
create trigger job_tracking_guard_conditions_insert
  before insert on public.job_tracking
  for each row execute function public.guard_tracking_conditions_insert();
