-- SUGO: push delivery targets
--
-- Realtime already tells a client their technician is delayed - but only while
-- the app is open. A push notification is the only way to reach someone who has
-- put their phone in their pocket, which is the entire point of announcing a
-- delay rather than waiting to be asked.
--
-- FCM addresses a DEVICE, not a user, so the server needs somewhere to look up
-- "which devices belong to this client". That is all this table is.
--
-- ## Why the token is unique, not the (user, token) pair
--
-- An FCM registration token identifies one app install. If a technician signs
-- out on a shared phone and a client signs in, FCM keeps issuing that same
-- token - it belongs to the install, not the account. Making `token` unique and
-- upserting on it MOVES the row to the new owner instead of leaving two rows
-- claiming the same device, which would have pushed one person's job updates to
-- whoever is holding the phone now.
--
-- ## Why rows are disposable
--
-- Tokens rotate, apps get uninstalled, and FCM answers `UNREGISTERED` for a
-- dead one. The sender deletes on that response, so this table self-cleans and
-- nothing here needs a scheduled sweep.

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null default 'android'
    check (platform in ('android', 'ios', 'web')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.device_tokens is
  'FCM registration tokens, one row per app install. Upserted on `token` so a '
  'device that changes hands moves to its new owner rather than duplicating.';

create index if not exists idx_device_tokens_user
  on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- A user reads and removes only their own devices. The sender runs on the
-- service role and bypasses these, which is how it reads the CLIENT's tokens
-- while the TECHNICIAN's session is the one that triggered the delay sample.
drop policy if exists "device_tokens_select_own" on public.device_tokens;
create policy "device_tokens_select_own"
  on public.device_tokens for select to authenticated
  using (user_id = auth.uid());

-- Sign-out removes the device, so a shared phone stops receiving the previous
-- account's notifications the moment they leave.
drop policy if exists "device_tokens_delete_own" on public.device_tokens;
create policy "device_tokens_delete_own"
  on public.device_tokens for delete to authenticated
  using (user_id = auth.uid());

-- There are deliberately NO insert or update policies: registration goes
-- through the function below instead. See why.

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
--
-- WHY A FUNCTION RATHER THAN AN INSERT POLICY.
--
-- `token` is unique per app install, and the row has to MOVE when a device
-- changes hands. Under plain RLS that is impossible: an `on conflict (token)
-- do update` would need to rewrite a row still owned by the previous user, and
-- `using (user_id = auth.uid())` correctly refuses. The result would be a
-- device permanently stuck on whoever signed in first - the shared-phone case,
-- and the crashed-before-sign-out case.
--
-- Signing out deletes the row and handles the tidy version of this. This
-- function handles the untidy one.
--
-- Reassigning to the caller is the right resolution, not a hole: FCM issued
-- this token to the app the caller is signed into right now, so they are
-- holding the device. The worst an attacker who somehow learned a token can do
-- is route THEIR OWN notifications to that handset - a nuisance, not a
-- disclosure, since they gain nothing about the previous owner.

create or replace function public.register_device_token(
  p_token text,
  p_platform text default 'android'
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  -- SECURITY DEFINER means RLS is not consulted, so the caller is checked here.
  if auth.uid() is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  if coalesce(trim(p_token), '') = '' then
    raise exception 'A device token is required' using errcode = '22023';
  end if;

  insert into public.device_tokens (user_id, token, platform)
  values (auth.uid(), p_token, coalesce(nullif(trim(p_platform), ''), 'android'))
  on conflict (token) do update
    set user_id = auth.uid(),
        platform = excluded.platform,
        updated_at = now();
end;
$function$;

comment on function public.register_device_token(text, text) is
  'Registers this device against the calling user, moving it from a previous '
  'owner if the install changed hands. The only write path into device_tokens.';

revoke all on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;
