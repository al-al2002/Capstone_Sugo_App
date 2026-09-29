-- SUGO: let a technician remove a specialisation they no longer want
--
-- ## The problem
--
-- `technician_specializations` could only be deleted while `verified = false`.
-- That was defensible when one assessment verified one row - deleting it would
-- have discarded the attempt history that justified it.
--
-- Tracks (20260907000008) made it untenable. One pass now verifies EVERY brand
-- in the track at once, so a technician who passed `computer_repair` after
-- mistakenly adding "Desktop / MSI" could never remove it. Six rows locked by
-- a single quiz, with no way back.
--
-- ## Why it was locked, and how that is now solved
--
-- `technician_assessment_results.specialization_id` was `not null` with
-- `on delete cascade`. Deleting the referenced specialisation therefore erased
-- the attempt rows - which is how a technician could have dodged the 24-hour
-- retake cooldown: fail, delete the specialisation, re-add it, sit it again
-- immediately.
--
-- Since 20260907000008 the attempt history is keyed on `track`, not on a
-- particular specialisation row. `specialization_id` is now only a pointer to
-- one of the rows the attempt covered, so it can become null without losing
-- anything that matters. The cooldown reads `track` and survives.

-- ---------------------------------------------------------------------------
-- 1. Attempt history outlives the row that started it
-- ---------------------------------------------------------------------------

alter table public.technician_assessment_results
  alter column specialization_id drop not null;

alter table public.technician_assessment_results
  drop constraint if exists technician_assessment_results_specialization_id_fkey;

alter table public.technician_assessment_results
  add constraint technician_assessment_results_specialization_id_fkey
  foreign key (specialization_id)
  references public.technician_specializations(id)
  on delete set null;

comment on column public.technician_assessment_results.specialization_id is
  'One of the specialisations the attempt covered, kept for reference only. '
  'Null once that row is removed. The attempt itself is keyed on `track`, so '
  'the retake cooldown survives a technician editing their specialisation list.';

-- `technician_id` keeps its cascade: if the account goes, so does everything.

-- ---------------------------------------------------------------------------
-- 2. Any of your own specialisations may be removed
-- ---------------------------------------------------------------------------
--
-- The `verified = false` condition is dropped. What it was protecting - the
-- attempt history - is protected by section 1 instead, and by a rule that does
-- not also punish an honest correction.

drop policy if exists "technician_specializations_delete_unverified"
  on public.technician_specializations;

drop policy if exists "technician_specializations_delete_own"
  on public.technician_specializations;
create policy "technician_specializations_delete_own"
  on public.technician_specializations for delete to authenticated
  using (technician_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3. Re-adding a brand in a track you already passed
-- ---------------------------------------------------------------------------
--
-- Without this, removing "Desktop / MSI" and adding it back would leave it
-- unverified for ever: the track is already passed, so
-- `record_assessment_result()` refuses to re-sit it ("already been passed"),
-- and nothing else awards the level. The technician would be stuck with a
-- permanently unproven row.
--
-- The rule is simply the track model applied consistently: passing a track
-- qualifies you for everything in it, whenever you declare it.
--
-- WHY AN AFTER TRIGGER, AND WHY SECURITY DEFINER. The insert policy pins
-- `verified = false` and `skill_level is null` on the incoming row, so the app
-- can never award itself anything - that check must stay. A BEFORE trigger
-- setting `verified = true` would be evaluated by that same WITH CHECK and be
-- rejected. Running afterwards, as the definer, keeps the strict insert policy
-- while letting the server grant what the technician has genuinely earned.

create or replace function public.inherit_track_verification()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_level text;
begin
  -- The most recent passing result for this technician on this track.
  select public.assessment_skill_level(r.score) into v_level
  from public.technician_assessment_results r
  where r.technician_id = new.technician_id
    and r.track = new.track
    and r.passed
  order by r.taken_at desc
  limit 1;

  if v_level is not null then
    update public.technician_specializations
    set verified = true,
        skill_level = v_level
    where id = new.id;
  end if;

  return null;  -- AFTER trigger; the return value is ignored.
end;
$function$;

drop trigger if exists technician_specializations_inherit_verification
  on public.technician_specializations;
create trigger technician_specializations_inherit_verification
  after insert on public.technician_specializations
  for each row execute function public.inherit_track_verification();
