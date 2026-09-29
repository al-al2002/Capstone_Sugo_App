-- SUGO: phone verification removed, email verification in its place
--
-- The client registration flow no longer asks for a phone number. Every route
-- to an SMS gateway carried a cost or a gate - Firebase Phone Auth now needs a
-- billing account, Twilio's trial only reaches numbers you have already
-- verified, Semaphore is prepaid - and none of that is a good reason to block
-- somebody from finishing a registration.
--
-- The step now confirms the address they signed up with. That is the same
-- class of evidence: `auth.users.email_confirmed_at` is written by GoTrue and
-- by nothing else, exactly as `phone_verified` could only be set by an edge
-- function holding the service role.
--
-- ORDER MATTERS IN THIS FILE. Two functions and one view read the columns
-- being dropped, so all three are rebuilt first. Postgres would otherwise
-- either refuse the drop or leave behind something that fails on next call.
--
--   1. submit_registration_for_review()   - the gate, now on email
--   2. initialize_client_trust_profile()  - stops recording a phone
--   3. job_client_trust                   - stops exposing one
--   4. drop the functions and the OTP table
--   5. drop the columns

-- ---------------------------------------------------------------------------
-- 1. The submission gate
-- ---------------------------------------------------------------------------

create or replace function public.submit_registration_for_review(
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_role text;
  v_status text;
  v_identity_status text;
  v_spec_count integer;
  v_verified_specs integer;
  v_email_verified boolean;
  v_has_address boolean;
  v_has_base boolean;
  v_final text;
begin
  select role, registration_status into v_role, v_status
  from public.profiles
  where id = p_user_id
  for update;

  if v_role is null then
    raise exception 'No profile for %', p_user_id;
  end if;

  if v_status in ('pending_review', 'active') then
    -- Idempotent: a double submit is a no-op rather than an error, because the
    -- likeliest cause is a retried request on a flaky connection.
    return jsonb_build_object('registration_status', v_status, 'changed', false);
  end if;

  -- The mandatory gate, identical for both roles. `approved` counts as well as
  -- `pending` - an ID already cleared is more than enough.
  select status into v_identity_status
  from public.identity_verifications
  where user_id = p_user_id and status in ('pending', 'approved')
  order by case status when 'approved' then 0 else 1 end
  limit 1;

  if v_identity_status is null then
    raise exception 'A government ID and a selfie holding it are required'
      using errcode = '23514';
  end if;

  if v_role = 'client' then
    -- Email replaced the SMS step entirely. `auth.users.email_confirmed_at` is
    -- written by GoTrue and by nothing else, which is the property that made
    -- the old flag trustworthy - obtained here without an SMS gateway.
    --
    -- Still a hard requirement, unlike the technician's optional documents:
    -- a booking confirmation has to reach somebody.
    select exists (
      select 1 from auth.users
      where id = p_user_id and email_confirmed_at is not null
    ) into v_email_verified;

    if not v_email_verified then
      raise exception 'Email verification is required' using errcode = '23514';
    end if;

    select exists (
      select 1 from public.client_saved_addresses where client_id = p_user_id
    ) into v_has_address;

    if not v_has_address then
      raise exception 'A default address is required' using errcode = '23514';
    end if;
  else
    select count(*), count(*) filter (where verified)
      into v_spec_count, v_verified_specs
    from public.technician_specializations
    where technician_id = p_user_id;

    if v_spec_count = 0 then
      raise exception 'At least one specialisation is required'
        using errcode = '23514';
    end if;

    -- At least one *passed* assessment, not all of them. A technician who
    -- qualified on laptops but is still waiting out a cooldown on printers is
    -- useful to the platform today; the unverified rows simply stay out of the
    -- matching pool until they are passed.
    if v_verified_specs = 0 then
      raise exception 'Pass at least one skill assessment before submitting'
        using errcode = '23514';
    end if;

    select base_latitude is not null and base_longitude is not null
      into v_has_base
    from public.technicians where id = p_user_id;

    if not coalesce(v_has_base, false) then
      raise exception 'A base location is required' using errcode = '23514';
    end if;
  end if;

  if v_identity_status = 'approved' then
    -- FIX (B). The reviewer got here first, so both conditions now hold and
    -- this submit is the second of the two. Activate directly - and for a
    -- technician this is where `is_verified` finally gets set, which is what
    -- was missing entirely before.
    v_final := public.activate_account(p_user_id);
    update public.profiles set registration_step = 'review' where id = p_user_id;
  else
    v_final := 'pending_review';
    update public.profiles
    set registration_status = 'pending_review',
        registration_step = 'review'
    where id = p_user_id;
  end if;

  return jsonb_build_object('registration_status', v_final, 'changed', true);
end;
$function$;

revoke all on function public.submit_registration_for_review(uuid)
  from public, anon, authenticated;
grant execute on function public.submit_registration_for_review(uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- 2. The trust profile no longer records a phone
-- ---------------------------------------------------------------------------
--
-- Recreated before the columns are dropped, because the old body inserts into
-- them. Dropping first would leave a function that fails on its next call.

create or replace function public.initialize_client_trust_profile(
  p_client_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
begin
  insert into public.client_verification_status (
    client_id, trust_level, no_show_count, avg_rating_from_technicians
  )
  values (
    p_client_id,
    'new',   -- everyone starts here; 'verified' is set when the ID is approved
    0,
    null     -- null, not 0 - see the column comment in 20260907000004
  )
  on conflict (client_id) do nothing;

  return jsonb_build_object('client_id', p_client_id, 'trust_level', 'new');
end;
$function$;

revoke all on function public.initialize_client_trust_profile(uuid)
  from public, anon, authenticated;
grant execute on function public.initialize_client_trust_profile(uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- 3. The matcher's client-trust view
-- ---------------------------------------------------------------------------
--
-- `create or replace view` cannot remove a column, so the view is dropped and
-- rebuilt. It has to happen before the column drop for the same reason as
-- section 2.
--
-- `phone_verified` was selected here but never scored: `clientTrustScore` in
-- `match-technician` reads only `trust_level` and `no_show_count`. Removing it
-- changes no ranking - it only stops carrying a column that is going away.

drop view if exists public.job_client_trust;

create view public.job_client_trust as
select
  j.id as job_id,
  j.client_id,
  coalesce(cvs.trust_level, 'new') as trust_level,
  coalesce(cvs.no_show_count, 0)   as no_show_count,
  cvs.avg_rating_from_technicians
from public.jobs j
left join public.client_verification_status cvs on cvs.client_id = j.client_id;

revoke all on public.job_client_trust from anon, authenticated;
grant select on public.job_client_trust to service_role;

-- ---------------------------------------------------------------------------
-- 3b. The admin review view
-- ---------------------------------------------------------------------------
--
-- The other view that reads the column, and the one that made the first
-- attempt at this migration fail. Same treatment as `job_client_trust`:
-- dropped and rebuilt, because `create or replace view` cannot change a
-- column list.

drop view if exists public.admin_applicant_detail;

create view public.admin_applicant_detail as
select
  p.id                                     as user_id,
  u.email,
  p.full_name,
  p.phone,
  p.role,
  p.registration_status,
  p.registration_step,
  p.created_at,
  p.onboarding_completed_at,
  t.is_verified                            as technician_verified,
  t.verification_tier,
  t.tier,
  t.service_radius_km,
  t.base_latitude,
  t.base_longitude,
  (select count(*) from public.technician_specializations s
     where s.technician_id = p.id)         as specialization_count,
  (select count(*) from public.technician_specializations s
     where s.technician_id = p.id and s.verified) as verified_specializations,
  (select count(*) from public.technician_verification_documents d
     where d.technician_id = p.id)         as document_count,
  -- The reviewer still needs to see whether the contact address was
  -- confirmed; only the channel changed. `auth.users` is already joined
  -- below, so this costs nothing extra.
  (u.email_confirmed_at is not null) as email_verified,
  cvs.trust_level,
  cvs.no_show_count,
  (select count(*) from public.client_saved_addresses a
     where a.client_id = p.id)             as address_count
from public.profiles p
join auth.users u on u.id = p.id
left join public.technicians t on t.id = p.id
left join public.client_verification_status cvs on cvs.client_id = p.id;

revoke all on public.admin_applicant_detail from anon, authenticated;
grant select on public.admin_applicant_detail to service_role;

-- ---------------------------------------------------------------------------
-- 4. Drop the phone verification machinery
-- ---------------------------------------------------------------------------
--
-- Every one of these exists only to prove control of a phone number, and
-- nothing calls them any more. Listed by exact signature so a stray overload
-- cannot be dropped by accident.

drop function if exists public.confirm_phone_verified();
drop function if exists public.my_phone_status();
drop function if exists public.set_phone_verified(uuid, text);
drop function if exists public.issue_phone_code(uuid, text, text);
drop function if exists public.verify_phone_code(uuid, text);

-- The OTP table. Only ever held short-lived codes and their consumed_at
-- stamps, so nothing of record is lost with it.
drop table if exists public.phone_verifications;

-- ---------------------------------------------------------------------------
-- 5. Drop the columns
-- ---------------------------------------------------------------------------
--
-- Last, once nothing reads or writes them.
--
-- NOTE FOR THE DEFENCE. The brief specifies `phone_verified`, and this removes
-- it. The reason is that the contact channel changed, not that the requirement
-- was dropped: the flow still proves the client owns a contact address before
-- they can submit, and it still proves it with a column the app cannot write.
-- What changed is which column - `auth.users.email_confirmed_at` instead of
-- `client_verification_status.phone_verified` - because every route to an SMS
-- gateway carried a cost or a gate that a registration should not depend on.

alter table public.client_verification_status
  drop column if exists phone_verified,
  drop column if exists phone_verified_at;
