-- =============================================================================
-- Push notifications for chat, pickup stages and the client's return choice
-- =============================================================================
--
-- Until now push reached a phone for one thing only: a technician running late
-- (20260916000004). Everything else arrived over Realtime, which only reaches
-- an OPEN app. This adds the notifications people need when the app is closed:
--
--   * a new chat message                    -> the other person on the job
--   * a pickup job changing stage           -> the client
--     (on the way, collected, to the shop, being repaired, out for delivery,
--      ready for pick-up, delivered)
--   * the client choosing pickup or delivery -> the technician
--
-- Being booked and a job being completed are pushed by `job-response` itself,
-- which already runs as server code for those actions; no trigger is needed,
-- and none is put on the frozen RB-CARS tables.
--
-- ## Why triggers
--
-- The three writes above come straight from the apps under RLS - a message
-- insert, the technician's stage update, the client's RPC. There is no server
-- code of ours in their path. A trigger is the one place that sees every one of
-- them, from any build of either app.
--
-- ## How
--
-- Each trigger calls `push_event()`, which posts the event - ids only - to the
-- `notify-event` edge function through `pg_net`. That is asynchronous: the
-- request is queued and sent after the transaction, so a slow or failing push
-- never slows or fails the write. It carries the `cron_secret` Vault entry the
-- ETA sweep already uses (20260916000005), which `notify-event` checks, so
-- nothing else can make SUGO notify people. The function reads the recipient
-- and the wording from the database itself.
-- =============================================================================

create extension if not exists pg_net;


-- ---------------------------------------------------------------------------
-- 1. The one outbound call
-- ---------------------------------------------------------------------------

create or replace function public.push_event(p_event jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'cron_secret';

  -- No secret, no push: the same "a missing key disables a feature, it never
  -- breaks the caller" rule the FCM and TomTom clients follow.
  if v_secret is null then
    return;
  end if;

  perform net.http_post(
    url := 'https://nlchvhygejurjvuyluwe.supabase.co/functions/v1/notify-event',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      -- The project's PUBLISHABLE key, as the ETA cron sends: it only gets the
      -- request through the gateway. The secret below is what authorises it.
      'Authorization', 'Bearer sb_publishable_debyibYaljXo1fNyaVyC3g_Ede2Stcu',
      'x-cron-secret', v_secret
    ),
    body := p_event,
    timeout_milliseconds := 10000
  );
exception when others then
  -- A notification is a courtesy on top of a write that has already happened.
  -- It must never be the reason that write fails.
  raise warning 'push_event failed: %', sqlerrm;
end;
$function$;

comment on function public.push_event(jsonb) is
  'Queues a push notification for an event, via pg_net to notify-event. '
  'Never raises. Called only by triggers.';

revoke all on function public.push_event(jsonb) from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- 2. A new chat message
-- ---------------------------------------------------------------------------

create or replace function public.push_on_job_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  perform public.push_event(
    jsonb_build_object('type', 'message', 'message_id', new.id)
  );
  return new;
end;
$function$;

drop trigger if exists job_messages_push on public.job_messages;
create trigger job_messages_push
  after insert on public.job_messages
  for each row execute function public.push_on_job_message();


-- ---------------------------------------------------------------------------
-- 3. A pickup job moving
-- ---------------------------------------------------------------------------
--
-- On insert (the technician sets off) and on a CHANGE of stage - not on every
-- position update, which rewrites this row every few seconds while driving.

create or replace function public.push_on_tracking_stage()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if tg_op = 'INSERT' or new.stage is distinct from old.stage then
    perform public.push_event(
      jsonb_build_object('type', 'stage', 'job_id', new.job_id, 'stage', new.stage)
    );
  end if;
  return new;
end;
$function$;

drop trigger if exists job_tracking_push on public.job_tracking;
create trigger job_tracking_push
  after insert or update of stage on public.job_tracking
  for each row execute function public.push_on_tracking_stage();


-- ---------------------------------------------------------------------------
-- 4. The client choosing pickup or delivery
-- ---------------------------------------------------------------------------

create or replace function public.push_on_return_method()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if tg_op = 'INSERT' or new.method is distinct from old.method then
    perform public.push_event(
      jsonb_build_object('type', 'return_method', 'job_id', new.job_id, 'method', new.method)
    );
  end if;
  return new;
end;
$function$;

drop trigger if exists job_return_preferences_push on public.job_return_preferences;
create trigger job_return_preferences_push
  after insert or update of method on public.job_return_preferences
  for each row execute function public.push_on_return_method();
