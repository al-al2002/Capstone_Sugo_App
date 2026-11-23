-- =============================================================================
-- Every skill assessment must be passed before a technician submits
-- =============================================================================
--
-- Asked for by the user on 2026-11-22 ("they answer all the assessment, not
-- only one"), choosing "pass all of them" when asked.
--
-- WHY
--
-- Until now registration needed only ONE passed assessment
-- (20260922000001: "At least one *passed* assessment, not all of them"). A
-- technician could pick Computer Repair, Phone Repair and Appliance Service,
-- pass only Computer Repair, and be admitted with the other two listed as
-- unassessed claims. The paper promises competency verification before a
-- technician accepts jobs, so every skill they list must now be proven.
--
-- WHAT CHANGES
--
-- submit_registration_for_review() refuses a technician while any of their
-- assessment groups (tracks) has no verified specialisation. A track counts as
-- passed once its assessment is passed: `record_assessment_result()` verifies
-- every row in the track, and `inherit_track_verification()` (20260907000009)
-- verifies a brand added to an already-passed track. So "every track passed"
-- and "every listed skill verified" are the same thing.
--
-- A technician who fails one has two ways forward, both in the app: retake it
-- after the 24-hour cooldown, or remove that skill and submit with the rest.
--
-- WHAT DOES NOT CHANGE
--
-- Accounts already `pending_review` or `active` are untouched - the function
-- returns early for both - so nobody already admitted is pulled out. The rule
-- applies the next time someone submits. The error uses errcode 23514, which
-- the `submit-registration` edge function relays word for word, so no
-- function redeploy is needed.
-- =============================================================================

-- Identical to the 20260922000001 version except for the assessment check.
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
  v_unpassed_tracks integer;
  v_has_clearance boolean;
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
    select count(*) into v_spec_count
    from public.technician_specializations
    where technician_id = p_user_id;

    if v_spec_count = 0 then
      raise exception 'At least one specialisation is required'
        using errcode = '23514';
    end if;

    -- NEW (20261122000003): every assessment group passed, not just one.
    select count(*) into v_unpassed_tracks
    from (
      select s.track
      from public.technician_specializations s
      where s.technician_id = p_user_id
        and s.track is not null
      group by s.track
      having not bool_or(s.verified)
    ) unpassed;

    if v_unpassed_tracks > 0 then
      raise exception
        'Pass every skill assessment before submitting (% still to pass), or remove the skills you have not passed',
        v_unpassed_tracks
        using errcode = '23514';
    end if;

    select exists (
      select 1 from public.technician_verification_documents
      where technician_id = p_user_id
        and doc_type = 'nbi_clearance'
        and status in ('pending', 'approved')
    ) into v_has_clearance;

    if not v_has_clearance then
      raise exception 'An NBI or police clearance is required'
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
