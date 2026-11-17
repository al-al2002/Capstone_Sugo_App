-- SUGO: pass an unanswered URGENT request to the next technician (2026-11-17)
--
-- The user's rule: an urgent job's technician gets a hard notification and
-- five minutes to accept; if they do not, the system sends the request to
-- another technician. The work is done by the `urgent-offer-sweep` edge
-- function (see its header); this only calls it on a timer.
--
-- ## Every 30 seconds
--
-- The deadline is `job_matches.offered_at` + 5 minutes. A one-minute cron
-- would pass a request on anywhere up to six minutes after it was sent;
-- every 30 seconds keeps it within half a minute of the countdown the app
-- shows. pg_cron 1.5+ takes a seconds interval, and Supabase ships 1.6.
--
-- ## No schema change
--
-- `offered_at` already exists (20261115000002) and `jobs.urgency` already
-- says urgent (`need_today`). A lapsed request is marked `declined`, a status
-- the table already allows. The frozen RB-CARS tables are not altered.
--
-- ## Auth
--
-- The same pattern as `20260916000005_tracking_eta_cron.sql`: the publishable
-- key gets through the gateway, and `x-cron-secret` (read from Vault, where
-- `cron_secret` already lives) is what the function checks.

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  perform cron.unschedule('sugo-urgent-offer-sweep');
exception
  when others then null;  -- not scheduled yet, which is the normal first run
end
$$;

select cron.schedule(
  'sugo-urgent-offer-sweep',
  '30 seconds',
  $cron$
  select net.http_post(
    url := 'https://nlchvhygejurjvuyluwe.supabase.co/functions/v1/urgent-offer-sweep',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable_debyibYaljXo1fNyaVyC3g_Ede2Stcu',
      'x-cron-secret', (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'cron_secret'
      )
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 20000
  );
  $cron$
);
