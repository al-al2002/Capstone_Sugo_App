-- =============================================================================
-- The NBI / police clearance becomes a server-side requirement
-- =============================================================================
--
-- WHY
--
-- The technician app has required a clearance since the documents step was
-- built (`verification_documents_step.dart`: "An NBI or police clearance is
-- required"), but the database never did. `submit_registration_for_review()`
-- checked the ID, a specialisation, a passed assessment and a base location -
-- and nothing about documents. So the rule existed only in one screen of one
-- client. Anyone calling the `submit-registration` edge function directly, or
-- an older build of the app, could reach the review queue without it.
--
-- The reasoning for making this the one mandatory document is the app's own:
-- it is about SAFETY, not skill. A technician is let into a stranger's home,
-- and the clearance is what the client is trusting when they open the door.
-- The certificate and the portfolio describe how good the work is, and stay
-- optional.
--
-- WHAT CHANGES
--
--   1. submit_registration_for_review() refuses a technician with no clearance
--      on file. "On file" means `pending` or `approved` - a clearance awaiting
--      review is enough to submit, exactly as a pending ID is, because the
--      reviewer decides both on the same screen.
--
--   2. The delete policy on `technician_verification_documents` stops the
--      clearance being removed once the registration is submitted. Without
--      this, (1) is a check that can be undone a second after it passes:
--      submit, delete the clearance, and be approved without one.
--
-- WHAT DOES NOT CHANGE
--
--   Accounts already `pending_review` or `active` are untouched: the function
--   returns early for both, and nobody is retroactively pulled out of the
--   marketplace. The rule applies the next time someone submits - a new
--   registration, or a resubmission after a rejection.
--
--   The error is raised with errcode 23514, which the `submit-registration`
--   edge function already relays word for word (REQUIREMENT_NOT_MET -> 409),
--   so no function redeploy is needed.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. The gate
-- ---------------------------------------------------------------------------
--
-- Identical to the 20260909000001 version except for the clearance check,
-- placed where the documents step sits in the technician flow (after skills
-- and assessment, before location), so the first missing thing reported is
-- the earliest one in the stepper.

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
    -- Email replaced the SMS step entirely. `auth.users.email_confirmed_at` is
    -- written by GoTrue and by nothing else, which is the property that made
    -- the old flag trustworthy - obtained here without an SMS gateway.
    --
    -- A hard requirement: a booking confirmation has to reach somebody.
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

    -- NEW. The clearance: the one document that gates a technician. Pending
    -- counts - it is reviewed alongside the ID - but a rejected one does not,
    -- since the reviewer has already said it is not acceptable.
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
    -- The reviewer got here first, so both conditions now hold and this submit
    -- is the second of the two. Activate directly - and for a technician this
    -- is where `is_verified` gets set.
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

-- `create or replace` keeps existing grants, but they are restated so this
-- file alone says who may call it. Service role only: the edge function runs
-- it on the caller's behalf after checking who they are.
revoke all on function public.submit_registration_for_review(uuid)
  from public, anon, authenticated;
grant execute on function public.submit_registration_for_review(uuid)
  to service_role;


-- ---------------------------------------------------------------------------
-- 2. The clearance cannot be deleted after submitting
-- ---------------------------------------------------------------------------
--
-- Replaces "verification_documents_delete_pending" from 20260907000003, which
-- let a technician delete any pending document at any time.
--
-- Other documents keep that freedom - withdrawing an optional certificate
-- harms nobody. The clearance may still be swapped out while the technician
-- is mid-registration (`incomplete`) or fixing a rejection (`rejected`),
-- which is when replacing a blurred scan is legitimate. Once they have
-- submitted (`pending_review`) or been admitted (`active`), it stays.
--
-- The subquery reads the caller's own profile row, which the profiles select
-- policy ("auth.uid() = id") already allows.

drop policy if exists "verification_documents_delete_pending"
  on public.technician_verification_documents;
create policy "verification_documents_delete_pending"
  on public.technician_verification_documents for delete to authenticated
  using (
    technician_id = auth.uid()
    and status = 'pending'
    and (
      doc_type <> 'nbi_clearance'
      or exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.registration_status in ('incomplete', 'rejected')
      )
    )
  );
