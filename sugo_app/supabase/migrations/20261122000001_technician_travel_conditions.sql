-- SUGO: will the technician still travel in the rain, or in heavy traffic?
-- (2026-11-22)
--
-- Approved by the user on 2026-11-22 ("yes"), after being told it needs new
-- columns on `technicians`, one of the frozen RB-CARS tables.
--
-- ## Why
--
-- The paper's Acceptance Likelihood table (Table 10/11) has a signal for
-- whether the technician can travel in the current weather. Until now the
-- matcher could only estimate it - how bad the weather is, times how long the
-- ride is - because nothing recorded what the technician themselves would do.
-- Registration now asks, and matching uses the answer when it is raining or
-- the traffic is heavy at the job.
--
-- ## What changes
--
-- 1. `technicians.rain_travel`:
--      'any'       - yes, even in heavy rain or a thunderstorm
--      'not_heavy' - yes in rain, but not in heavy rain or a storm
--      'never'     - does not travel in the rain
-- 2. `technicians.heavy_traffic_travel`: true = still goes in heavy traffic,
--    false = avoids it.
-- 3. `matching_candidates` carries both, so `match-technician` reads them
--    (it selects `*`).
--
-- Both are NULLABLE with no default, on purpose. Null means "not answered
-- yet", which is every technician registered before today. Matching treats
-- null exactly as it did before this migration - an estimate from the
-- weather and the trip - so nobody's ranking changes until they answer.
-- They can answer in Profile -> Edit profile.
--
-- No RLS change. A technician writes their own row through
-- `technicians_update_own`; `guard_technician_self_update()` lists the
-- columns they may NOT touch, and these are not among them.

-- ---------------------------------------------------------------------------
-- 1. The columns
-- ---------------------------------------------------------------------------

alter table public.technicians
  add column if not exists rain_travel text,
  add column if not exists heavy_traffic_travel boolean;

alter table public.technicians
  drop constraint if exists technicians_rain_travel_check;
alter table public.technicians
  add constraint technicians_rain_travel_check
  check (rain_travel is null or rain_travel in ('any', 'not_heavy', 'never'));

comment on column public.technicians.rain_travel is
  'Will they travel to a client in the rain? any = even in heavy rain or a '
  'storm; not_heavy = in rain but not heavy rain; never = not in the rain. '
  'Null = not answered. Read by match-technician (Weather & traffic '
  'readiness).';
comment on column public.technicians.heavy_traffic_travel is
  'Will they still travel when traffic is heavy? Null = not answered. Read by '
  'match-technician (Weather & traffic readiness).';

-- ---------------------------------------------------------------------------
-- 2. The candidate pool carries them
-- ---------------------------------------------------------------------------
--
-- Copied from 20261117000007; only the two appended columns are new.

create or replace view public.matching_candidates as
select
  t.id,
  t.skill_tags,
  t.tier,
  t.specialization,
  t.is_verified,
  t.is_available,
  t.badge,
  t.rating,
  t.total_jobs,
  t.current_workload,
  t.latitude,
  t.longitude,
  t.base_latitude,
  t.base_longitude,
  t.service_radius_km,
  t.verification_tier,
  t.created_at,
  p.full_name,
  p.avatar_url,
  p.phone,
  exists (
    select 1
    from public.identity_verifications iv
    where iv.user_id = t.id
      and iv.status = 'approved'
  ) as identity_approved,
  coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'device_type', s.device_type,
          'brand', s.brand,
          'skill_level', s.skill_level,
          'verified', s.verified,
          'track', s.track
        )
        order by s.created_at
      )
      from public.technician_specializations s
      where s.technician_id = t.id
    ),
    '[]'::jsonb
  ) as specializations,
  public.technician_away_until(t.id) as away_until,
  t.barangay,
  t.offers_home_service,
  t.offers_shop_repair,
  -- NEW (20261122000001): will they travel in rain / heavy traffic.
  -- Appended, as a replaced view may only add columns at the end.
  t.rain_travel,
  t.heavy_traffic_travel
from public.technicians t
join public.profiles p on p.id = t.id;

revoke all on public.matching_candidates from anon, authenticated;
grant select on public.matching_candidates to service_role;
