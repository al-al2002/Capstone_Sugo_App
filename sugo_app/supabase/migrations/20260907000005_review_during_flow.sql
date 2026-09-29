-- SUGO: let review run in parallel with the rest of registration
--
-- ## The problem this fixes
--
-- The ID + selfie step deliberately sits second, so nothing can skip it. But a
-- reviewer may take hours, and there is no reason a technician should sit idle
-- meanwhile - the specialisation, assessment, document and location steps have
-- nothing to do with identity. So the app now lets them carry on while review
-- runs.
--
-- That exposed two faults in `review_identity_verification()` as written in
-- 20260907000002, both confirmed against the live database before this fix:
--
--   A. Approving an ID while the account was still `incomplete` moved it
--      straight to `pending_review`. The router sends a `pending_review`
--      account to the waiting screen, so a technician who was halfway through
--      their assessment would be **locked out of finishing it**. A reviewer
--      doing their job promptly would strand the applicant.
--
--   B. Nothing ever set `technicians.is_verified`. The old comment said
--      20260907000003 owned that decision, but no function there does it -
--      `submit-assessment` stopped setting it (correctly, since a quiz does not
--      prove identity) and no replacement was written. An approved technician
--      would sit at `pending_review` for ever and could never reach the
--      dashboard.
--
-- ## The rule, stated once
--
-- Identity approval and registration completeness are two independent
-- conditions. An account goes live only when **both** hold, and whichever
-- happens second is what activates it.
--
--   approval arrives first  -> status untouched; the final submit activates
--   submission arrives first -> status pending_review; the approval activates
--
-- That is why both functions below end in the same `activate_account()` helper
-- rather than each having its own copy of the rule.

-- ---------------------------------------------------------------------------
-- 1. One place that turns an account on
-- ---------------------------------------------------------------------------
--
-- Called from both directions. Idempotent, because both callers can legitimately
-- reach it and the second one must not undo the first.

create or replace function public.activate_account(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_role text;
  v_now timestamptz := now();
  v_has_approved_doc boolean;
begin
  select role into v_role from public.profiles where id = p_user_id;

  update public.profiles
  set registration_status = 'active',
      onboarding_completed_at = coalesce(onboarding_completed_at, v_now)
  where id = p_user_id;

  if v_role = 'technician' then
    -- `is_verified` is what admits a technician to the RB-CARS matching pool.
    -- Set here and nowhere else: reaching this point means a human approved
    -- their identity AND `submit_registration_for_review()` confirmed they
    -- passed at least one assessment. Neither condition alone is enough, which
    -- is exactly why `submit-assessment` no longer sets it.
    select exists (
      select 1 from public.technician_verification_documents
      where technician_id = p_user_id
        and status = 'approved'
        and doc_type in ('certificate', 'nbi_clearance')
    ) into v_has_approved_doc;

    update public.technicians
    set is_verified = true,
        -- basic  = identity approved (never reached here, since activation
        --          already implies a passed assessment)
        -- verified = identity + assessment
        -- certified_pro = + an approved certificate or NBI clearance
        verification_tier = case
          when v_has_approved_doc then 'certified_pro'
          else 'verified'
        end
    where id = p_user_id;
  end if;

  return 'active';
end;
$function$;

revoke all on function public.activate_account(uuid)
  from public, anon, authenticated;
grant execute on function public.activate_account(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 2. Reviewing an identity no longer strands a half-finished applicant
-- ---------------------------------------------------------------------------

create or replace function public.review_identity_verification(
  p_verification_id uuid,
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
  v_user_id uuid;
  v_role text;
  v_status text;
  v_now timestamptz := now();
  v_new_status text;
begin
  select iv.user_id, iv.role, p.registration_status
    into v_user_id, v_role, v_status
  from public.identity_verifications iv
  join public.profiles p on p.id = iv.user_id
  where iv.id = p_verification_id
  for update of iv;

  if v_user_id is null then
    raise exception 'No such identity verification: %', p_verification_id;
  end if;

  if not p_approved and coalesce(trim(p_notes), '') = '' then
    -- A rejection with no reason is unusable: the retake screen has nothing to
    -- tell the user, so they resubmit the same photos and are rejected again.
    raise exception 'A rejection must include a reason for the applicant';
  end if;

  update public.identity_verifications
  set status = case when p_approved then 'approved' else 'rejected' end,
      admin_notes = p_notes,
      reviewed_by = p_reviewer_id,
      reviewed_at = v_now
  where id = p_verification_id;

  if not p_approved then
    -- A rejection always wins, whatever else the account had finished. The
    -- router sends `rejected` back to the identity step with the reviewer's
    -- note, which is the only thing that matters until it is resolved.
    update public.profiles
    set registration_status = 'rejected'
    where id = v_user_id;

    v_new_status := 'rejected';

  elsif v_status = 'pending_review' then
    -- They had already submitted everything and were waiting on exactly this.
    -- `submit_registration_for_review()` validated the rest, so approval is
    -- the last condition and the account goes live.
    v_new_status := public.activate_account(v_user_id);

  else
    -- FIX (A). Still working through the flow. Their identity is approved -
    -- recorded on the verification row above - but the registration is not
    -- finished, so the account status is deliberately left alone. Moving it to
    -- `pending_review` here is what used to lock them out of the remaining
    -- steps. Their final submit will activate them without a second review.
    v_new_status := v_status;
  end if;

  return jsonb_build_object(
    'user_id', v_user_id,
    'role', v_role,
    'approved', p_approved,
    'registration_status', v_new_status,
    'reviewed_at', v_now
  );
end;
$function$;

revoke all on function public.review_identity_verification(uuid, boolean, uuid, text)
  from public, anon, authenticated;
grant execute on function public.review_identity_verification(uuid, boolean, uuid, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 3. Submitting when the ID was already approved
-- ---------------------------------------------------------------------------
--
-- The mirror image of the same rule. If a reviewer got there first, there is
-- nothing left for a human to look at, so queueing the account for a second
-- review would leave it waiting on a decision that has already been made.
--
-- Identical to the 20260907000004 version except for the ending.

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
  v_phone_verified boolean;
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
    select coalesce(phone_verified, false) into v_phone_verified
    from public.client_verification_status where client_id = p_user_id;

    -- Unlike the technician's optional documents, phone verification is a hard
    -- requirement: it is the only channel a technician has to reach a client
    -- who is not at the pinned address when they arrive.
    if not coalesce(v_phone_verified, false) then
      raise exception 'Phone verification is required' using errcode = '23514';
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
-- 4. The guard has to allow the incomplete -> active jump
-- ---------------------------------------------------------------------------
--
-- `guard_registration_status()` blocks a user from changing their own status
-- to anything but `pending_review`, which is still exactly right. But note
-- what the new flow does: an account whose ID was approved mid-flow goes from
-- `incomplete` straight to `active` without ever passing through
-- `pending_review`.
--
-- That transition is made by `activate_account()` on the service role, where
-- `auth.uid()` is null and the guard exempts the caller - so no change is
-- needed. This block exists to say so out loud, because "why does the guard
-- not list this transition?" is the obvious question to ask of the code above,
-- and the answer is that no user can ever make it.
--
-- Re-asserted verbatim so the reasoning lives next to the rule.

comment on function public.guard_registration_status() is
  'Blocks a user from changing their own registration_status to anything but '
  'pending_review. incomplete -> active is legitimate but is only ever made by '
  'activate_account() on the service role, where auth.uid() is null and this '
  'guard exempts the caller.';
