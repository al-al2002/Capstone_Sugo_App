-- SUGO: one formula for a technician's rating, not two kept "in step"
--
-- 20260917000001 recomputes `technicians.rating` in SQL when a review changes,
-- and `refreshTechnicianAggregates` in job-response recomputed it in TypeScript
-- when a job completed. The migration described the two as the same formula.
-- They were not quite: JavaScript averages and rounds a binary float, Postgres
-- rounds an exact `numeric`, and an average such as 4.335 can land on 4.33 in
-- one and 4.34 in the other. Whichever ran last would win, by a cent.
--
-- Immaterial to a ranking, but "these two must stay in step" is a promise that
-- decays the first time someone edits one side. So the edge function now calls
-- `recompute_technician_rating` instead of carrying its own copy, and there is
-- exactly one definition of the number.
--
-- 20260917000001 revoked EXECUTE from PUBLIC, which also removed the default
-- grant `service_role` inherits. It is granted back explicitly here - to the
-- server role only, so the app still cannot trigger a recompute on demand.

grant execute on function public.recompute_technician_rating(uuid) to service_role;
