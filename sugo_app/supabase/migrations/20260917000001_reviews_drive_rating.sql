-- SUGO: client ratings finally reach the scores that rank technicians
--
-- ## The bug
--
-- Nothing in the app ever recorded a rating. Every technician on the live
-- project was rated 0.00, including those with completed jobs, and so were the
-- inputs to three things that depend on it:
--
--   * `technicians.rating` - the recommended row's primary sort key, and the
--     matcher's `rating` factor (weight 0.12 in scoring/constants.ts);
--   * `job_outcomes.final_rating` - summed by scoring/accuracy.ts into Stage 1;
--   * the technician dashboard's ratings strip, which reads the same column.
--
-- Two separate gaps produced it:
--
--   1. `job-response` accepts `final_rating` only from the CLIENT who posted
--      the job - correct, a technician must not rate themselves - but the only
--      caller of `complete` in the app is the TECHNICIAN'S dashboard. So the
--      rating was always discarded as `null`.
--   2. `job_reviews` (20260916000001) had a reader, a star breakdown and a
--      profile screen, and no writer anywhere.
--
-- ## The fix
--
-- The client's review becomes the rating. When a review is written, changed or
-- withdrawn, this trigger:
--
--   * mirrors its stars into `job_outcomes.final_rating` for that job - the
--     column Stage 1 and the dashboard strip already read, so neither needs to
--     learn a new source; and
--   * recomputes `technicians.rating` with EXACTLY the formula
--     `refreshTechnicianAggregates` in job-response uses: the mean of the
--     non-null `final_rating`s, rounded to 2 dp, 0 when there are none.
--
-- Using the same formula over the same column is what stops the two writers
-- fighting. When a later job completes and the edge function recomputes the
-- average, it arrives at the same number this trigger did, instead of resetting
-- the rating to 0 as it would have while `final_rating` was always null.
--
-- Every `completed` job has an outcome row to mirror into: `handleComplete` is
-- the only path to that status and it writes the outcome first. And a review
-- can only exist for a completed job (the insert policy checks it), so the
-- mirror is always 1:1.

-- ---------------------------------------------------------------------------
-- 1. First, close the hole that this would otherwise make exploitable
-- ---------------------------------------------------------------------------
--
-- The update policy from 20260916000001 carried a comment claiming that
-- `technician_id` and `job_id` were "pinned by the same check as the insert".
-- They were not: its WITH CHECK only tested `reviewer_id = auth.uid()`. A client
-- could edit their review and move it onto any technician at all.
--
-- That was a data-integrity bug while reviews were only displayed. Once reviews
-- set `technicians.rating` it becomes a way to sink a competitor's ranking with
-- one-star reviews for jobs they never did. So it is fixed here, before the
-- trigger below exists.
--
-- Column privileges rather than a stricter policy, because what should be true
-- is simply "a review's identity never changes" - a review is ABOUT one job and
-- one technician, and an edit may change what was said, never who it was said
-- about. RLS filters rows; only column grants can say that. The same technique
-- already protects the assessment answer key in 20260906000001.

revoke update on public.job_reviews from authenticated;
grant update (stars, comment) on public.job_reviews to authenticated;

-- Default Supabase grants include TRUNCATE, which RLS does not govern at all.
-- It is not reachable through PostgREST, so this is defence in depth rather than
-- a live hole, but a table whose rows now move rankings should not rely on the
-- API layer for that.
revoke truncate on public.job_reviews from anon, authenticated;

-- The policy itself is re-stated with the relationship checked, so the rule is
-- enforced in two independent places and the comment is finally true.
drop policy if exists "job_reviews_update_own" on public.job_reviews;
create policy "job_reviews_update_own"
  on public.job_reviews for update to authenticated
  using (reviewer_id = auth.uid())
  with check (
    reviewer_id = auth.uid()
    and exists (
      select 1 from public.jobs j
      where j.id = job_id
        and j.client_id = auth.uid()
        and j.status = 'completed'
        and j.assigned_technician_id = job_reviews.technician_id
    )
  );

-- ---------------------------------------------------------------------------
-- 2. One definition of a technician's rating
-- ---------------------------------------------------------------------------

create or replace function public.recompute_technician_rating(
  p_technician_id uuid
)
returns void
language sql
security definer
set search_path = public
as $function$
  -- Keep in step with `refreshTechnicianAggregates` in job-response/index.ts.
  -- Both must compute the mean of non-null final_rating, 2 dp, 0 when empty,
  -- or whichever ran last would win.
  update public.technicians
  set rating = coalesce(
    (
      select round(avg(o.final_rating)::numeric, 2)
      from public.job_outcomes o
      where o.technician_id = p_technician_id
        and o.final_rating is not null
    ),
    0
  )
  where id = p_technician_id;
$function$;

comment on function public.recompute_technician_rating(uuid) is
  'Sets technicians.rating to the mean of that technician''s rated outcomes. '
  'Same formula as refreshTechnicianAggregates in job-response.';

-- Server-side only. Nothing in the app should be able to ask for a recompute on
-- demand; it happens as a consequence of a review, not as a request.
revoke all on function public.recompute_technician_rating(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. A review moves the scores
-- ---------------------------------------------------------------------------
--
-- WHY SECURITY DEFINER. The review is written from the CLIENT's session. That
-- client may not update `job_outcomes` (no update policy - by design, see the
-- RB-CARS schema) or another person's `technicians` row. Running as the owner
-- is what lets a legitimate review reach them, and the only input it trusts is
-- a row that already passed the job_reviews policies above.
--
-- WHY IT PASSES THE TECHNICIANS GUARD. `guard_technician_self_update` only
-- refuses when `auth.uid()` IS the technician editing their own row. Here
-- `auth.uid()` is the client, so the guard lets it through - and a technician
-- still cannot rate themselves, because the insert policy requires the reviewer
-- to be the job's client.

create or replace function public.sync_review_to_scoring()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if tg_op = 'DELETE' then
    -- A withdrawn review withdraws the rating with it.
    update public.job_outcomes
    set final_rating = null
    where job_id = old.job_id
      and technician_id = old.technician_id;

    perform public.recompute_technician_rating(old.technician_id);
    return null;
  end if;

  update public.job_outcomes
  set final_rating = new.stars
  where job_id = new.job_id
    and technician_id = new.technician_id;

  perform public.recompute_technician_rating(new.technician_id);

  -- Unreachable now that the identity columns cannot be updated, and kept
  -- anyway: if that grant is ever loosened, the technician the review was moved
  -- AWAY from must not keep a rating it no longer earns.
  if tg_op = 'UPDATE' and old.technician_id is distinct from new.technician_id then
    perform public.recompute_technician_rating(old.technician_id);
  end if;

  return null;  -- AFTER trigger; the return value is ignored.
end;
$function$;

drop trigger if exists job_reviews_sync_scoring on public.job_reviews;
create trigger job_reviews_sync_scoring
  after insert or update or delete on public.job_reviews
  for each row execute function public.sync_review_to_scoring();
