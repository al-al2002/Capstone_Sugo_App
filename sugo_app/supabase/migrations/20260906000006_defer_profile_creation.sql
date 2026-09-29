-- SUGO: write nothing to the database until registration is finished
--
-- ## What changes
--
-- Until now, signing up created a `profiles` row instantly via the
-- `on_auth_user_created` trigger, and each onboarding step wrote its own piece
-- as the person went. Abandoning halfway left a trail across `profiles`,
-- `technicians` and `technician_assessments`.
--
-- Now nothing is written until the whole flow completes. The trigger is
-- removed, the app holds the answers in memory, and one transactional function
-- writes every row at the end - or writes none of them.
--
-- ## What this cannot change
--
-- `auth.users` is still created by Supabase at sign-up, before any of this can
-- run. There is no way around that: Storage RLS and every table policy key off
-- `auth.uid()`, so the person must be authenticated before they can upload an
-- ID or be scored. What we control is the `public` schema - the tables that
-- appear in the Table Editor - and those now stay completely clean until the
-- end.
--
-- Orphaned `auth.users` rows with no profile are cleaned up by
-- `purge-abandoned-signups`, which now looks for exactly that shape.

-- ---------------------------------------------------------------------------
-- 1. Stop creating profiles at sign-up
-- ---------------------------------------------------------------------------
--
-- The trigger was the whole reason a half-finished signup left a row behind.
-- The function is kept, unused, so the old behaviour can be restored with a
-- single `create trigger` if this proves too strict.

drop trigger if exists on_auth_user_created on auth.users;

comment on function public.handle_new_user() is
  'No longer attached to a trigger. Profile creation moved to '
  'public.complete_registration() so an abandoned signup writes nothing. '
  'Re-attach to auth.users only if reverting to instant profile creation.';

-- ---------------------------------------------------------------------------
-- 2. One transactional write for the whole registration
-- ---------------------------------------------------------------------------
--
-- WHY A POSTGRES FUNCTION AND NOT SEVERAL CLIENT CALLS. A technician's
-- registration touches three tables. Done as three statements from the edge
-- function, a failure on the third leaves the first two behind - the exact
-- partial state this migration exists to prevent.
--
-- A plpgsql function runs inside a single implicit transaction. Either every
-- row appears or none does, enforced by the database rather than by careful
-- ordering in application code.
--
-- SECURITY DEFINER because it writes tables whose policies would otherwise
-- reject an insert (`technicians` requires the starting state, and
-- `technician_assessments` is written with a verdict the caller must not be
-- able to choose). The edge function is the only caller and has already
-- verified the identity and scored the quiz itself.

create or replace function public.complete_registration(
  p_user_id uuid,
  p_role text,
  p_full_name text,
  p_phone text,
  p_id_document_url text,
  p_specialization text default null,
  p_answers jsonb default null,
  p_score numeric default null,
  p_total_questions integer default null,
  p_tier text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_now timestamptz := now();
begin
  if p_role not in ('client', 'technician') then
    raise exception 'Invalid role: %', p_role;
  end if;

  if p_id_document_url is null or length(p_id_document_url) = 0 then
    raise exception 'An identity document is required';
  end if;

  -- The profile. `onboarding_completed_at` is set in the same statement that
  -- creates the row: there is no moment where a profile exists but is
  -- unfinished, which is the entire point of this migration.
  insert into public.profiles (
    id, full_name, phone, role, role_chosen_at,
    id_document_url, id_submitted_at, onboarding_completed_at
  )
  values (
    p_user_id, p_full_name, p_phone, p_role, v_now,
    p_id_document_url, v_now, v_now
  )
  on conflict (id) do update
    set full_name = coalesce(excluded.full_name, public.profiles.full_name),
        phone = coalesce(excluded.phone, public.profiles.phone),
        role = excluded.role,
        role_chosen_at = coalesce(public.profiles.role_chosen_at, v_now),
        id_document_url = excluded.id_document_url,
        id_submitted_at = v_now,
        onboarding_completed_at =
          coalesce(public.profiles.onboarding_completed_at, v_now);

  if p_role = 'client' then
    return jsonb_build_object('role', 'client', 'completed_at', v_now);
  end if;

  -- ------------------------------------------------------------ technician
  if p_specialization is null then
    raise exception 'A specialisation is required for technicians';
  end if;
  if p_tier is null then
    raise exception 'A tier is required for technicians';
  end if;

  insert into public.technicians (
    id, specialization, tier, is_verified, is_available,
    id_document_url, id_submitted_at
  )
  values (
    p_user_id, array[p_specialization], p_tier, true, false,
    p_id_document_url, v_now
  )
  on conflict (id) do update
    set specialization = excluded.specialization,
        tier = excluded.tier,
        is_verified = true,
        id_document_url = excluded.id_document_url,
        id_submitted_at = v_now;

  -- The passing attempt. Only successful attempts are recorded now: a failed
  -- one would have to be stored against a technician row that, by design, does
  -- not exist yet.
  insert into public.technician_assessments (
    technician_id, specialization, answers, score,
    total_questions, passed, suggested_tier
  )
  values (
    p_user_id, p_specialization, coalesce(p_answers, '{}'::jsonb),
    coalesce(p_score, 0), coalesce(p_total_questions, 0), true, p_tier
  );

  return jsonb_build_object(
    'role', 'technician',
    'tier', p_tier,
    'completed_at', v_now
  );
end;
$function$;

-- Only the service role may call it. The edge function is the sole entry
-- point, and it authenticates the caller and scores the quiz before doing so.
revoke all on function public.complete_registration(
  uuid, text, text, text, text, text, jsonb, numeric, integer, text
) from public, anon, authenticated;

grant execute on function public.complete_registration(
  uuid, text, text, text, text, text, jsonb, numeric, integer, text
) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Abandoned signups are now auth rows with no profile
-- ---------------------------------------------------------------------------
--
-- The old `incomplete_signups` view looked for profiles with a null completion
-- stamp. With deferred creation there is no profile at all, so the view would
-- always be empty and the purge would never find anything. Replaced with a
-- view over `auth.users` that have no matching profile.

drop view if exists public.incomplete_signups;

create or replace view public.incomplete_signups as
select
  u.id,
  u.email,
  u.created_at,
  u.last_sign_in_at,
  now() - u.created_at as age
from auth.users u
where not exists (
  select 1 from public.profiles p where p.id = u.id
);

comment on view public.incomplete_signups is
  'Authenticated accounts that never finished registration, so no profile row '
  'was ever created. Read by purge-abandoned-signups.';

revoke all on public.incomplete_signups from anon, authenticated;
grant select on public.incomplete_signups to service_role;
