-- SUGO: schedule the ETA sweep
--
-- Delay detection was driven entirely by the technician's position stream, so
-- it stopped working in the one case it exists for: a technician who is not
-- moving. Stuck in gridlock, app backgrounded, phone out of signal - no fixes
-- arrive, nothing resamples, and the client is never told.
--
-- This schedules `tracking-eta-sweep`, which resamples any travelling leg that
-- has gone quiet, from its last known position.
--
-- ## Why every two minutes
--
-- It matches the app's own sampling cadence, so a healthy delivery and a
-- stalled one are measured at the same rate. The sweep only picks up legs that
-- have missed their own updates by a clear margin (`STALE_AFTER_MS` = 4 min in
-- the function), so on a normal delivery this fires, finds nothing, and costs
-- one edge-function invocation - about 21k a month against a 500k allowance.
--
-- ## Why the secret comes from Vault
--
-- pg_cron has to authenticate to the function, and whatever it uses is stored
-- in the `cron.job` table as plain text. Putting `SUPABASE_SERVICE_ROLE_KEY`
-- there would write a credential that bypasses every RLS policy into an
-- ordinary table, to buy one privilege: "may trigger a sweep".
--
-- So the cron carries `CRON_SECRET` instead, read from Vault at call time and
-- never written into this file. Anyone who obtains it can make the server
-- recompute ETAs it was about to recompute anyway.
--
-- The secret is created out of band - deliberately NOT in this migration, so it
-- never enters the repository:
--
--   select vault.create_secret('<value>', 'cron_secret');
--
-- If it is missing the header is null, the function answers 401, and the sweep
-- is simply inactive. Nothing else breaks.
--
-- The publishable key below is not a secret - it already ships inside the app
-- in `app_env.dart`. It is here only to satisfy the API gateway, which rejects
-- an unauthenticated request before the function runs.

-- ---------------------------------------------------------------------------
-- 1. Extensions
-- ---------------------------------------------------------------------------

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------------------------------------------------------------------------
-- 2. The schedule
-- ---------------------------------------------------------------------------
--
-- Unscheduled first so the migration is re-runnable: `cron.schedule` on an
-- existing name behaves differently across pg_cron versions, and a duplicate
-- job would double the sweep rate rather than fail loudly.

do $$
begin
  perform cron.unschedule('sugo-tracking-eta-sweep');
exception
  when others then null;  -- not scheduled yet, which is the normal first run
end
$$;

select cron.schedule(
  'sugo-tracking-eta-sweep',
  '*/2 * * * *',
  $cron$
  select net.http_post(
    url := 'https://nlchvhygejurjvuyluwe.supabase.co/functions/v1/tracking-eta-sweep',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable_debyibYaljXo1fNyaVyC3g_Ede2Stcu',
      'x-cron-secret', (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'cron_secret'
      )
    ),
    body := '{}'::jsonb,
    -- Longer than the function's own provider timeouts, so a slow TomTom is
    -- not recorded here as a network failure.
    timeout_milliseconds := 20000
  );
  $cron$
);

comment on extension pg_cron is
  'Runs the tracking ETA sweep. See 20260916000005_tracking_eta_cron.sql.';
