-- SUGO: a repaired unit does not always have to be delivered
--
-- The tracking stages were a straight line that always ended in a delivery:
--
--   heading_to_pickup -> collected -> returning_to_shop -> in_repair
--     -> out_for_delivery -> delivered
--
-- So a client who would rather collect their own laptop from the shop - because
-- they work next door, or they want it today rather than when the technician
-- is free - had no way to say so, and the technician had no way to record it.
-- The only route to `delivered` was a trip somebody had to make.
--
-- ## The branch
--
-- `in_repair` now has two exits:
--
--   in_repair -> out_for_delivery      -> delivered   (the technician brings it)
--   in_repair -> ready_for_collection  -> delivered   (the client comes to get it)
--
-- Both converge on `delivered`, so nothing downstream has to learn a second
-- ending: `delivered` still means "the client has it".
--
-- ## Why it shows no map
--
-- Nothing travels in this stage. The unit is sitting on a shelf waiting to be
-- picked up, so a live map would show a stationary pin over the workshop for
-- however long that takes - which reads as a stalled technician rather than as
-- a repair that is finished and waiting. The client screen shows the shop
-- address instead, which is the thing they actually need.
--
-- For the same reason `tracking-eta` must not sweep it: there is no journey to
-- be late for. Its `TRAVELLING_STAGES` list is explicit rather than "everything
-- except delivered", so this stage is excluded by construction.
--
-- ## Not one of the frozen four
--
-- `job_tracking` was added in 20260906000007, well after the RB-CARS schema.
-- Widening its CHECK is an ordinary change, not a change to the frozen core.

alter table public.job_tracking
  drop constraint if exists job_tracking_stage_check;

alter table public.job_tracking
  add constraint job_tracking_stage_check
  check (stage in (
    'heading_to_pickup',    -- on the way to collect the unit
    'collected',            -- unit in hand, heading back
    'returning_to_shop',
    'in_repair',            -- at the bench; no travel, so no map
    'out_for_delivery',     -- repaired, on the way back to the client
    'ready_for_collection', -- repaired, waiting for the client at the shop
    'delivered'             -- the client has it, by either route
  ));

comment on column public.job_tracking.stage is
  'Where the unit is. After in_repair the flow branches: out_for_delivery when '
  'the technician brings it back, ready_for_collection when the client comes '
  'to the shop. Both end at delivered.';
