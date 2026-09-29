-- SUGO: trust Supabase Auth for phone verification
--
-- The client registration phone step moves from our own OTP table to Supabase
-- Auth's phone provider (`updateUser(phone:)` + `verifyOTP(phoneChange)`).
--
-- ## Why the app cannot just set the flag
--
-- `client_verification_status` has no insert or update policy for
-- `authenticated`, on purpose: every column on it is either awarded
-- (`trust_level`), earned (`avg_rating_from_technicians`) or held against the
-- client (`no_show_count`). A self-writable `phone_verified` would let anyone
-- skip the step by writing `true`.
--
-- So the app reports "I verified my phone" and the DATABASE checks it, against
-- `auth.users.phone_confirmed_at` - a column only GoTrue writes, and only
-- after it has matched a real OTP. The client's claim is never the evidence.

-- ---------------------------------------------------------------------------
-- 1. Confirm a phone against Supabase Auth
-- ---------------------------------------------------------------------------

create or replace function public.confirm_phone_verified()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_phone text;
  v_confirmed timestamptz;
begin
  if v_uid is null then
    raise exception 'Sign in required';
  end if;

  -- The evidence. `phone_confirmed_at` is set by GoTrue when it accepts an
  -- OTP, and by nothing else - not by us, and not by the client.
  select u.phone, u.phone_confirmed_at
    into v_phone, v_confirmed
  from auth.users u
  where u.id = v_uid;

  if v_confirmed is null then
    raise exception 'This phone number has not been verified yet'
      using errcode = '23514';
  end if;

  -- Mirror onto `profiles`, which is where the rest of the app reads a phone
  -- number from. GoTrue stores it without the leading '+', so it is restored
  -- to E.164 for consistency with everything else in this schema.
  update public.profiles
  set phone = case
        when v_phone is null then phone
        when left(v_phone, 1) = '+' then v_phone
        else '+' || v_phone
      end
  where id = v_uid;

  insert into public.client_verification_status (
    client_id, phone_verified, phone_verified_at
  )
  values (v_uid, true, v_confirmed)
  on conflict (client_id) do update
    set phone_verified = true,
        phone_verified_at = coalesce(
          public.client_verification_status.phone_verified_at, v_confirmed
        );

  return jsonb_build_object(
    'phone_verified', true,
    'phone', v_phone,
    'confirmed_at', v_confirmed
  );
end;
$function$;

-- Callable by the signed-in user: it grants nothing they have not already
-- earned, because it verifies the fact for itself before writing.
grant execute on function public.confirm_phone_verified() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The trust profile now accepts either source of truth
-- ---------------------------------------------------------------------------
--
-- `initialize_client_trust_profile()` decided `phone_verified` by looking for
-- a consumed row in our own `phone_verifications` table. Accounts verified
-- through Supabase Auth have no such row, so a client who used the new flow
-- would have had the flag reset to false at submit time - and
-- `submit_registration_for_review()` would then have refused their
-- registration for a step they had actually completed.
--
-- Both sources are accepted. The old table stays valid for anyone who
-- verified before this migration.

create or replace function public.initialize_client_trust_profile(
  p_client_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_phone_verified boolean;
  v_confirmed_at timestamptz;
begin
  -- Supabase Auth first: it is the path the app now uses.
  select u.phone_confirmed_at into v_confirmed_at
  from auth.users u where u.id = p_client_id;

  v_phone_verified := v_confirmed_at is not null;

  -- Fall back to the legacy OTP table.
  if not v_phone_verified then
    select exists (
      select 1 from public.phone_verifications
      where user_id = p_client_id and consumed_at is not null
    ) into v_phone_verified;
  end if;

  insert into public.client_verification_status (
    client_id, phone_verified, phone_verified_at, trust_level,
    no_show_count, avg_rating_from_technicians
  )
  values (
    p_client_id,
    v_phone_verified,
    case when v_phone_verified then coalesce(v_confirmed_at, now()) else null end,
    'new',
    0,
    null
  )
  on conflict (client_id) do update
    -- Never downgrade a flag that is already true: this runs at submit time,
    -- after the phone step, and must not undo it.
    set phone_verified = excluded.phone_verified or
                         public.client_verification_status.phone_verified,
        phone_verified_at = coalesce(
          public.client_verification_status.phone_verified_at,
          excluded.phone_verified_at
        );

  return jsonb_build_object('client_id', p_client_id, 'trust_level', 'new');
end;
$function$;

revoke all on function public.initialize_client_trust_profile(uuid)
  from public, anon, authenticated;
grant execute on function public.initialize_client_trust_profile(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Reading back the verified number
-- ---------------------------------------------------------------------------
--
-- The registration flow needs to know, on resume, whether the phone step is
-- already done. `auth.users` is not readable by the client, so this exposes
-- exactly the two facts the step needs and nothing else.

create or replace function public.my_phone_status()
returns jsonb
language sql
stable
security definer
set search_path = public
as $function$
  select jsonb_build_object(
    'phone', u.phone,
    'verified', u.phone_confirmed_at is not null
  )
  from auth.users u
  where u.id = auth.uid();
$function$;

grant execute on function public.my_phone_status() to authenticated;
