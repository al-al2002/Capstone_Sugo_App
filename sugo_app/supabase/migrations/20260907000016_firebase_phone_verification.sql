-- SUGO: record a phone number verified by Firebase
--
-- Phone OTP moves to Firebase Phone Auth, whose free tier sends real SMS. That
-- creates a problem the previous design did not have.
--
-- ## The problem
--
-- `confirm_phone_verified()` (20260907000015) trusts nothing the app says: it
-- re-reads `auth.users.phone_confirmed_at`, a column only GoTrue writes and
-- only after it has matched its own OTP. That is what made the flag
-- unforgeable.
--
-- Firebase never touches that column. It confirms the number in ITS OWN
-- project, so from Supabase's point of view there is no evidence at all - and
-- the obvious shortcut, letting the app report "Firebase said yes", is exactly
-- the self-certification the whole verification design exists to prevent.
--
-- ## The evidence that replaces it
--
-- A Firebase ID token. It is a JWT signed by Google with a key the caller does
-- not have, and it carries the verified `phone_number` as a claim. The
-- `verify-firebase-phone` edge function checks that signature against Google's
-- published keys before calling the function below.
--
-- So the chain is: Firebase proves the number -> Google's signature proves
-- Firebase said it -> the edge function checks the signature -> only then does
-- this function write the flag. The app is never the authority; it only
-- carries the token.

create or replace function public.set_phone_verified(
  p_user_id uuid,
  p_phone text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_exists boolean;
  v_now timestamptz := now();
begin
  if p_user_id is null then
    raise exception 'A user is required';
  end if;

  if coalesce(trim(p_phone), '') = '' then
    raise exception 'A phone number is required';
  end if;

  select exists (select 1 from public.profiles where id = p_user_id)
    into v_exists;

  if not v_exists then
    raise exception 'No profile for %', p_user_id;
  end if;

  -- `profiles.phone` is where the rest of the app reads a number from.
  update public.profiles
  set phone = p_phone
  where id = p_user_id;

  insert into public.client_verification_status (
    client_id, phone_verified, phone_verified_at
  )
  values (p_user_id, true, v_now)
  on conflict (client_id) do update
    set phone_verified = true,
        phone_verified_at = coalesce(
          public.client_verification_status.phone_verified_at, v_now
        );

  return jsonb_build_object(
    'phone_verified', true,
    'phone', p_phone,
    'confirmed_at', v_now
  );
end;
$function$;

-- Service role only. The whole point is that the app cannot call this - it has
-- to go through the edge function, which checks Google's signature first.
revoke all on function public.set_phone_verified(uuid, text)
  from public, anon, authenticated;
grant execute on function public.set_phone_verified(uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- Reading the step's state back
-- ---------------------------------------------------------------------------
--
-- `my_phone_status()` from 20260907000015 reads `auth.users`, which Firebase
-- never populates - so a client who verified through Firebase would be asked
-- again on every resume. It now answers from whichever source actually has the
-- fact.

create or replace function public.my_phone_status()
returns jsonb
language sql
stable
security definer
set search_path = public
as $function$
  select jsonb_build_object(
    -- Prefer the number recorded by whichever flow verified it. GoTrue stores
    -- its own without a leading '+'; `profiles.phone` is already E.164.
    'phone', coalesce(
      (select p.phone from public.profiles p where p.id = auth.uid()),
      (select u.phone from auth.users u where u.id = auth.uid())
    ),
    'verified', coalesce(
      -- Firebase path, written by set_phone_verified().
      (select cvs.phone_verified
         from public.client_verification_status cvs
        where cvs.client_id = auth.uid()),
      false
    )
    -- Supabase Auth path, for anyone who verified before the move.
    or (select u.phone_confirmed_at is not null
          from auth.users u where u.id = auth.uid())
  );
$function$;

grant execute on function public.my_phone_status() to authenticated;
