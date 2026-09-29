-- SUGO: the admin role and the review console's account
--
-- The Laravel admin panel keeps no database of its own. Its login, its
-- identity and every row it shows come from Supabase, so there is exactly one
-- account store for the whole system.
--
-- ## Why the admin is a `profiles` row and not a separate table
--
-- `identity_verifications.reviewed_by` and
-- `technician_verification_documents.reviewed_by` already reference
-- `profiles(id)`. Putting admins anywhere else would mean either a nullable
-- reference to nothing, or a second foreign key pointing at a different table
-- for the same column. An admin is a person with an account, like everybody
-- else - they just have a different role.

-- ---------------------------------------------------------------------------
-- 1. Widen the role constraint
-- ---------------------------------------------------------------------------

alter table public.profiles drop constraint if exists profiles_role_check;

alter table public.profiles
  add constraint profiles_role_check
  check (role in ('client', 'technician', 'admin'));

comment on column public.profiles.role is
  'client | technician | admin. An admin signs in to the Laravel review '
  'console, never to the mobile app.';

-- `handle_new_user()` is deliberately NOT changed. It maps anything that is
-- not an explicit 'technician' to 'client', so a hostile signup cannot mint an
-- admin by putting "admin" in its metadata. Admin accounts are created here,
-- by hand, and nowhere else.

-- ---------------------------------------------------------------------------
-- 2. The admin account
-- ---------------------------------------------------------------------------
--
-- Created directly in `auth.users` rather than through the Auth admin API, so
-- the whole thing is reproducible from `supabase db push` with no out-of-band
-- step. The password is bcrypt-hashed with pgcrypto, which is the same scheme
-- GoTrue uses, so a normal email/password sign-in works against it.
--
-- An `auth.identities` row is required as well. Without it GoTrue treats the
-- account as having no linked provider and the email/password grant fails,
-- which is the usual reason a hand-inserted user "exists but cannot log in".
--
-- SECURITY NOTE, stated rather than hidden: the password below is `admin123`,
-- which is weak and is committed to the repository. That is acceptable for a
-- capstone demonstration and nothing else. Before this is ever reachable from
-- a network, change it - see the runbook in docs/admin-panel.md.

create extension if not exists pgcrypto with schema extensions;

do $$
declare
  v_uid uuid;
  v_email text := 'admin@sugo.ph';
  v_password text := 'admin123';
begin
  select id into v_uid from auth.users where email = v_email;

  if v_uid is null then
    v_uid := gen_random_uuid();

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      is_sso_user, is_anonymous,
      -- These must be '' and never NULL. Postgres marks them nullable, but
      -- GoTrue scans them into non-nullable Go strings, so a NULL makes the
      -- sign-in query fail with "Database error querying schema" - a 500 that
      -- names neither the column nor the row. This is the single most common
      -- reason a hand-inserted Supabase user exists but cannot log in, and it
      -- cost a debugging round here before being pinned down.
      confirmation_token, recovery_token, email_change,
      email_change_token_new, email_change_token_current,
      phone_change, phone_change_token, reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000',
      v_uid, 'authenticated', 'authenticated', v_email,
      extensions.crypt(v_password, extensions.gen_salt('bf')),
      -- Confirmed on creation. There is no inbox to receive a confirmation
      -- link, and an unconfirmed account cannot sign in.
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"full_name":"SUGO Administrator"}'::jsonb,
      false, false,
      '', '', '', '', '', '', '', ''
    );

    insert into auth.identities (
      id, user_id, identity_data, provider, provider_id,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), v_uid,
      jsonb_build_object('sub', v_uid::text, 'email', v_email),
      'email', v_email, now(), now(), now()
    );
  else
    -- Re-running the migration resets the password rather than failing, so a
    -- forgotten demo password is one `db push` away from working again.
    update auth.users
    set encrypted_password = extensions.crypt(v_password, extensions.gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        updated_at = now()
    where id = v_uid;
  end if;

  -- The profile. `registration_status = 'active'` because an admin has no
  -- registration to complete, and `onboarding_completed_at` keeps them out of
  -- the abandoned-signup purge.
  insert into public.profiles (
    id, full_name, role, registration_status,
    role_chosen_at, onboarding_completed_at
  ) values (
    v_uid, 'SUGO Administrator', 'admin', 'active', now(), now()
  )
  on conflict (id) do update
    set role = 'admin',
        registration_status = 'active',
        full_name = coalesce(public.profiles.full_name, 'SUGO Administrator');
end $$;

-- ---------------------------------------------------------------------------
-- 3. Dashboard counters
-- ---------------------------------------------------------------------------
--
-- One round trip for the whole dashboard instead of six. The console reads
-- this through the service role, which bypasses RLS - so no policy is added,
-- and no ordinary user gains a way to count other people's accounts.

create or replace view public.admin_dashboard_stats as
select
  (select count(*) from public.identity_verifications where status = 'pending')      as pending_verifications,
  (select count(*) from public.identity_verifications where status = 'approved')     as approved_verifications,
  (select count(*) from public.identity_verifications where status = 'rejected')     as rejected_verifications,
  (select count(*) from public.profiles where role = 'technician')                   as total_technicians,
  (select count(*) from public.profiles where role = 'client')                       as total_clients,
  (select count(*) from public.profiles where registration_status = 'active')        as active_accounts,
  (select count(*) from public.profiles where registration_status = 'incomplete')    as incomplete_accounts,
  (select count(*) from public.profiles where registration_status = 'pending_review') as awaiting_review,
  (select count(*) from public.technicians where is_verified)                        as verified_technicians,
  (select count(*) from public.technician_verification_documents where status = 'pending') as pending_documents;

revoke all on public.admin_dashboard_stats from anon, authenticated;
grant select on public.admin_dashboard_stats to service_role;

-- ---------------------------------------------------------------------------
-- 4. The review queue, with everything the console renders
-- ---------------------------------------------------------------------------
--
-- Replaces `identity_review_queue` from 20260907000002, which listed only
-- pending rows. The console also needs the history tab - what was approved,
-- what was rejected and why - so the filter moves out of the view and into the
-- query the console makes.

create or replace view public.admin_verification_queue as
select
  iv.id                as verification_id,
  iv.user_id,
  iv.role,
  iv.status,
  iv.id_document_url,
  iv.selfie_with_id_url,
  iv.admin_notes,
  iv.submitted_at,
  iv.reviewed_at,
  iv.reviewed_by,
  p.full_name,
  p.phone,
  p.registration_status,
  u.email,
  reviewer.full_name   as reviewed_by_name,
  (
    select count(*)
    from public.identity_verifications prior
    where prior.user_id = iv.user_id
      and prior.submitted_at < iv.submitted_at
  ) + 1                as attempt_number,
  now() - iv.submitted_at as waiting_for
from public.identity_verifications iv
join public.profiles p        on p.id = iv.user_id
join auth.users u             on u.id = iv.user_id
left join public.profiles reviewer on reviewer.id = iv.reviewed_by;

comment on view public.admin_verification_queue is
  'Every ID + selfie submission with the applicant and reviewer resolved. '
  'Read by the Laravel console through the service role.';

revoke all on public.admin_verification_queue from anon, authenticated;
grant select on public.admin_verification_queue to service_role;

-- ---------------------------------------------------------------------------
-- 5. Applicant detail
-- ---------------------------------------------------------------------------
--
-- What a reviewer needs beside the photos to make a judgement: how far the
-- person got, and what they claim to be able to do. A technician with eight
-- declared specialisations and no passed assessment looks different from one
-- with a single passed expert-level brand, and the reviewer should see that.

create or replace view public.admin_applicant_detail as
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
  cvs.phone_verified,
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
-- 6. Reviewing a trust-boosting document
-- ---------------------------------------------------------------------------
--
-- The certificate / NBI / portfolio equivalent of
-- `review_identity_verification()`. Approving a certificate can promote a
-- technician to `certified_pro`, so like every other award this runs on the
-- service role and never on the technician's own session.

create or replace function public.review_verification_document(
  p_document_id uuid,
  p_approved boolean,
  p_reviewer_id uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_tech uuid;
  v_now timestamptz := now();
  v_is_active boolean;
  v_has_doc boolean;
begin
  select technician_id into v_tech
  from public.technician_verification_documents
  where id = p_document_id
  for update;

  if v_tech is null then
    raise exception 'No such document: %', p_document_id;
  end if;

  if not p_approved and coalesce(trim(p_notes), '') = '' then
    raise exception 'A rejection must include a reason for the technician';
  end if;

  update public.technician_verification_documents
  set status = case when p_approved then 'approved' else 'rejected' end,
      admin_notes = p_notes,
      reviewed_by = p_reviewer_id,
      reviewed_at = v_now
  where id = p_document_id;

  -- Promotion to certified_pro only applies to an account that is already
  -- live. A technician still mid-registration gets their tier computed by
  -- `activate_account()` when they finish, which reads the same condition.
  select registration_status = 'active' into v_is_active
  from public.profiles where id = v_tech;

  if p_approved and coalesce(v_is_active, false) then
    select exists (
      select 1 from public.technician_verification_documents
      where technician_id = v_tech
        and status = 'approved'
        and doc_type in ('certificate', 'nbi_clearance')
    ) into v_has_doc;

    if v_has_doc then
      update public.technicians
      set verification_tier = 'certified_pro'
      where id = v_tech and verification_tier <> 'certified_pro';
    end if;
  end if;

  return jsonb_build_object(
    'document_id', p_document_id,
    'technician_id', v_tech,
    'approved', p_approved,
    'reviewed_at', v_now
  );
end;
$function$;

revoke all on function public.review_verification_document(uuid, boolean, uuid, text)
  from public, anon, authenticated;
grant execute on function public.review_verification_document(uuid, boolean, uuid, text)
  to service_role;
