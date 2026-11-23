-- SUGO: technicians registered before the rain / heavy-traffic questions
-- are set to "they go". (2026-11-23)
--
-- ## Why
--
-- 20261122000001 added `technicians.rain_travel` and
-- `technicians.heavy_traffic_travel`, asked at the end of the registration
-- "Work type" step. Everyone who had already registered was left null ("not
-- answered"), which matching scores as an estimate from the weather and the
-- trip. The user asked for those technicians to be set to "they go":
--
--   rain_travel          = 'any'  - yes, even in heavy rain or a storm
--   heavy_traffic_travel = true   - yes, still goes in heavy traffic
--
-- On 2026-11-23 that was 6 technicians (3 active, 3 pending review), none of
-- whom had answered.
--
-- ## What it touches
--
-- Only technicians whose registration is finished (`pending_review` or
-- `active`), and only a column that is still null - an answer a technician
-- has already given is kept. Someone still mid-registration answers the
-- question themselves. Every technician can change the answer later in
-- Profile -> Edit profile.
--
-- No schema, RLS or function change. `guard_technician_self_update()` only
-- checks updates made by a signed-in technician, so it lets this through.

update public.technicians t
set rain_travel = coalesce(t.rain_travel, 'any'),
    heavy_traffic_travel = coalesce(t.heavy_traffic_travel, true)
from public.profiles p
where p.id = t.id
  and p.registration_status in ('pending_review', 'active')
  and (t.rain_travel is null or t.heavy_traffic_travel is null);
