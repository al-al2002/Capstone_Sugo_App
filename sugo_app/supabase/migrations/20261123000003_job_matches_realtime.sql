-- SUGO: the client's app hears a decline without a push. (2026-11-23)
--
-- ## Why
--
-- The user reported that the "can't take this one" pop-up never appeared
-- when a technician declined. It was raised only by the decline PUSH, and on
-- 2026-11-23 not one device had a push token (device_tokens was empty), and
-- the web build has no Firebase messaging set up at all - so the push, and
-- with it the pop-up, could never arrive while testing.
--
-- The app now also watches `job_matches` over Supabase Realtime while it is
-- open (`MatchDeclineWatcher`), the way chat and live tracking already do,
-- and raises the pop-up from that - push or no push.
--
-- ## What changes
--
-- Only this: `job_matches` joins the `supabase_realtime` publication. No
-- table, column, policy or function changes; the frozen RB-CARS schema is
-- untouched.
--
-- ## Who hears what
--
-- Realtime applies row-level security per subscriber. `job_matches` has RLS
-- on, and its only read policies are `job_matches_client_select` (the
-- client's own jobs) and `job_matches_technician_select` (the technician's
-- own offers) - checked on production before this was written. So a client
-- is only ever sent changes to matches on their own jobs, exactly what they
-- can already read.

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'job_matches'
    ) then
      alter publication supabase_realtime add table public.job_matches;
    end if;
  else
    raise notice 'supabase_realtime publication not found, skipping';
  end if;
end $$;
