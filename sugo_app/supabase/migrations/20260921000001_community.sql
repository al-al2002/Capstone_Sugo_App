-- SUGO: the Community Q&A feed
--
-- Replaces the Chat tab in both bottom bars. Direct job messaging is not
-- removed - it moves to where it belongs, on the job itself (Bookings -> a job
-- -> "Open chat"), which is the only place it was ever about.
--
-- The shape is deliberately asymmetric, because the two roles are here for
-- different reasons:
--
--   * A CLIENT asks. "What laptop specs should a student on a budget get?"
--     They cannot answer, because an answer from another client carries none
--     of the authority the feed exists to surface.
--   * A TECHNICIAN answers. Their reply is signed with their tier and their
--     reputation, which is what makes the feed worth reading rather than a
--     forum of strangers.
--   * A CLIENT rates the answers. Only the person who asked the question, and
--     their peers who have the same problem, can say whether an answer helped.
--
-- ---------------------------------------------------------------------------
-- WHY REPUTATION IS ITS OWN TABLE
-- ---------------------------------------------------------------------------
--
-- The obvious move is `alter table technicians add column reputation_points`.
-- This migration deliberately does not do that, for two reasons.
--
-- 1. `technicians` is one of the four RB-CARS tables, and that schema is
--    frozen. A community feature has no business widening it.
--
-- 2. More importantly, it makes a design promise enforceable. Community points
--    must never influence who gets offered a job - otherwise a technician can
--    farm upvotes into paid work, and the matching score stops meaning what
--    the RB-CARS document says it means. Keeping the number in a table the
--    matcher does not read makes that structural. "It cannot affect ranking"
--    is a far better answer than "it does not currently affect ranking",
--    because the second one is one careless join away from being false.

-- ---------------------------------------------------------------------------
-- 1. Who is asking
-- ---------------------------------------------------------------------------
--
-- `profiles` is readable only by its owner, so every policy below needs a
-- SECURITY DEFINER hop to learn a caller's role - exactly the pattern
-- `is_job_participant` established in 20260907000013.

create or replace function public.profile_role(p_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $function$
  select p.role from public.profiles p where p.id = p_id;
$function$;

comment on function public.profile_role(uuid) is
  'The role on a profile row. SECURITY DEFINER because `profiles` is readable '
  'only by its owner, so a policy cannot join to it directly.';

grant execute on function public.profile_role(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Questions
-- ---------------------------------------------------------------------------

create table if not exists public.community_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,

  title text not null check (
    length(trim(title)) between 8 and 160
  ),
  body text not null check (
    length(trim(body)) between 10 and 4000
  ),

  -- A small fixed set rather than free tags. Free tags on a feed this size
  -- fragment into "laptop", "Laptop" and "laptops" within a week, and the
  -- filter row then has thirty entries and sorts nothing.
  topic text not null default 'general' check (
    topic in ('general', 'laptop', 'phone', 'appliance', 'network', 'buying')
  ),

  -- Denormalised so the feed does not run a count per row. Maintained by the
  -- trigger in section 5; never written by the app.
  comment_count integer not null default 0,

  -- Bumped when an answer lands, so "Recent" means recent *activity* and a
  -- question that is still being answered does not sink below a dead one.
  last_activity_at timestamptz not null default now(),

  created_at timestamptz not null default now()
);

comment on table public.community_posts is
  'Client questions in the Community feed. Clients ask; technicians answer.';

create index if not exists idx_community_posts_recent
  on public.community_posts (last_activity_at desc);

create index if not exists idx_community_posts_topic
  on public.community_posts (topic, last_activity_at desc);

alter table public.community_posts enable row level security;

-- The feed is readable by every signed-in user. That is the point of it: a
-- technician who cannot read the questions cannot answer them.
drop policy if exists "community_posts_select_all" on public.community_posts;
create policy "community_posts_select_all"
  on public.community_posts for select to authenticated
  using (true);

-- Clients only. `author_id = auth.uid()` stops a post being attributed to
-- someone else; the role check is what keeps the feed a place where questions
-- come from the people with the problems.
drop policy if exists "community_posts_insert_client" on public.community_posts;
create policy "community_posts_insert_client"
  on public.community_posts for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.profile_role(auth.uid()) = 'client'
  );

drop policy if exists "community_posts_update_own" on public.community_posts;
create policy "community_posts_update_own"
  on public.community_posts for update to authenticated
  using (author_id = auth.uid());

drop policy if exists "community_posts_delete_own" on public.community_posts;
create policy "community_posts_delete_own"
  on public.community_posts for delete to authenticated
  using (author_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3. Answers
-- ---------------------------------------------------------------------------

create table if not exists public.community_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,

  body text not null check (
    length(trim(body)) between 2 and 4000
  ),

  -- Frozen at insert from the author's profile.
  --
  -- WHY IT IS STORED AND NOT JOINED. Voting rules and reputation both depend
  -- on "was this answer written by a technician?", and that must be settled
  -- when the answer is written. A role read live from `profiles` would mean a
  -- client who later registers as a technician retroactively turns every
  -- comment they ever posted into a votable, points-earning answer.
  author_role text not null check (author_role in ('client', 'technician', 'admin')),

  -- Denormalised, maintained by the trigger in section 5.
  helpful_count integer not null default 0,

  created_at timestamptz not null default now()
);

comment on table public.community_comments is
  'Answers on a community post. `author_role` is frozen at insert because the '
  'voting and reputation rules depend on it.';

create index if not exists idx_community_comments_post
  on public.community_comments (post_id, created_at);

-- "Most Helpful" sort within a thread.
create index if not exists idx_community_comments_helpful
  on public.community_comments (post_id, helpful_count desc, created_at);

-- Reputation totals, which sum a technician's answers.
create index if not exists idx_community_comments_author
  on public.community_comments (author_id);

alter table public.community_comments enable row level security;

drop policy if exists "community_comments_select_all" on public.community_comments;
create policy "community_comments_select_all"
  on public.community_comments for select to authenticated
  using (true);

-- Anyone signed in may answer, but `author_role` must be their *real* role -
-- it cannot be asserted by the client, or a client would simply post their
-- own answers as 'technician' and vote them up.
drop policy if exists "community_comments_insert_own" on public.community_comments;
create policy "community_comments_insert_own"
  on public.community_comments for insert to authenticated
  with check (
    author_id = auth.uid()
    and author_role = public.profile_role(auth.uid())
  );

drop policy if exists "community_comments_delete_own" on public.community_comments;
create policy "community_comments_delete_own"
  on public.community_comments for delete to authenticated
  using (author_id = auth.uid());

-- No update policy. An answer that has been voted on is a record other people
-- acted on, and silently rewriting it after the fact would make every vote
-- attached to it a lie.

-- ---------------------------------------------------------------------------
-- 4. Votes
-- ---------------------------------------------------------------------------
--
-- WHY A THUMBS UP AND NOT A STAR RATING
--
-- A five-star score on an *answer* is ambiguous in a way it is not on a
-- completed repair: three stars on "did this help?" means nothing anybody can
-- act on, and it invites the same rating inflation that makes star averages
-- on marketplaces cluster meaninglessly between 4.4 and 4.9.
--
-- "Was this helpful?" has one honest answer and one honest silence. It is one
-- tap, it makes "Most Helpful" a plain count, and it makes reputation a plain
-- multiple of it. The absence of a downvote is deliberate too: a technician's
-- livelihood is attached to this profile, and a brigading mechanism is not
-- something a marketplace should ship.

create table if not exists public.community_votes (
  comment_id uuid not null references public.community_comments(id) on delete cascade,
  voter_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),

  -- One vote per person per answer, enforced by the key itself rather than by
  -- a policy that could be worked around with a race.
  primary key (comment_id, voter_id)
);

comment on table public.community_votes is
  'One helpful-vote per client per answer. Presence is the vote; there is no '
  'downvote and no score column.';

create index if not exists idx_community_votes_voter
  on public.community_votes (voter_id);

alter table public.community_votes enable row level security;

-- Everyone can read votes, which is what lets the UI show the caller whether
-- they have already voted. The aggregate lives on the comment row.
drop policy if exists "community_votes_select_all" on public.community_votes;
create policy "community_votes_select_all"
  on public.community_votes for select to authenticated
  using (true);

-- Four conditions, and all four matter:
--
--   1. the vote is cast by the caller,
--   2. the caller is a client - technicians do not rank each other,
--   3. the answer was written by a technician - there is no reputation to
--      award otherwise,
--   4. nobody votes on their own answer.
--
-- (3) and (4) together are what close the self-dealing loop.
drop policy if exists "community_votes_insert_client" on public.community_votes;
create policy "community_votes_insert_client"
  on public.community_votes for insert to authenticated
  with check (
    voter_id = auth.uid()
    and public.profile_role(auth.uid()) = 'client'
    and exists (
      select 1 from public.community_comments c
      where c.id = comment_id
        and c.author_role = 'technician'
        and c.author_id <> auth.uid()
    )
  );

-- Un-voting is allowed. A rating you cannot take back is one people hesitate
-- to give.
drop policy if exists "community_votes_delete_own" on public.community_votes;
create policy "community_votes_delete_own"
  on public.community_votes for delete to authenticated
  using (voter_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 5. Reputation
-- ---------------------------------------------------------------------------

create table if not exists public.community_reputation (
  technician_id uuid primary key references public.profiles(id) on delete cascade,

  points integer not null default 0 check (points >= 0),
  helpful_votes integer not null default 0 check (helpful_votes >= 0),
  answers integer not null default 0 check (answers >= 0),

  updated_at timestamptz not null default now()
);

comment on table public.community_reputation is
  'Community standing per technician. Deliberately NOT a column on '
  '`technicians`: the RB-CARS matcher does not read this table, which is what '
  'guarantees community points can never influence job ranking.';

alter table public.community_reputation enable row level security;

-- World-readable, because a technician's standing is shown next to every
-- answer they write. Nothing here is private.
drop policy if exists "community_reputation_select_all" on public.community_reputation;
create policy "community_reputation_select_all"
  on public.community_reputation for select to authenticated
  using (true);

-- No insert, update or delete policy for anyone. The table is maintained
-- exclusively by the SECURITY DEFINER triggers below, so points cannot be
-- written by the app at all - which is the only way a points economy stays
-- honest.

-- Points awarded per helpful vote.
--
-- Small on purpose. The number needs to be visibly more than zero and
-- meaningfully less than what completing a paid job is worth, or the feed
-- starts competing with the actual work.
create or replace function public.community_points_per_vote()
returns integer
language sql
immutable
as $function$ select 5; $function$;

create or replace function public.recalc_community_reputation(p_technician uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_answers integer;
  v_votes   integer;
begin
  -- Recomputed from source rather than incremented.
  --
  -- An increment is one missed trigger away from a total that never
  -- reconciles, and a wrong reputation is worse than a slow one. The counts
  -- are indexed and a technician has tens of answers, not millions.
  select count(*), coalesce(sum(c.helpful_count), 0)
    into v_answers, v_votes
  from public.community_comments c
  where c.author_id = p_technician
    and c.author_role = 'technician';

  insert into public.community_reputation
    (technician_id, points, helpful_votes, answers, updated_at)
  values (
    p_technician,
    v_votes * public.community_points_per_vote(),
    v_votes,
    v_answers,
    now()
  )
  on conflict (technician_id) do update set
    points        = excluded.points,
    helpful_votes = excluded.helpful_votes,
    answers       = excluded.answers,
    updated_at    = now();
end;
$function$;

-- Vote -> comment tally -> reputation.
create or replace function public.sync_community_vote()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_comment uuid;
  v_author  uuid;
begin
  v_comment := coalesce(new.comment_id, old.comment_id);

  update public.community_comments c
  set helpful_count = (
    select count(*) from public.community_votes v where v.comment_id = c.id
  )
  where c.id = v_comment
  returning c.author_id into v_author;

  if v_author is not null then
    perform public.recalc_community_reputation(v_author);
  end if;

  return coalesce(new, old);
end;
$function$;

drop trigger if exists community_votes_sync on public.community_votes;
create trigger community_votes_sync
  after insert or delete on public.community_votes
  for each row execute function public.sync_community_vote();

-- Answer -> post tally, and the author's answer count.
create or replace function public.sync_community_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_post uuid;
begin
  v_post := coalesce(new.post_id, old.post_id);

  update public.community_posts p
  set comment_count = (
        select count(*) from public.community_comments c where c.post_id = p.id
      ),
      -- Only a new answer counts as activity. A deletion bumping the post to
      -- the top of "Recent" would be exactly backwards.
      last_activity_at = case
        when tg_op = 'INSERT' then now() else p.last_activity_at
      end
  where p.id = v_post;

  if coalesce(new.author_role, old.author_role) = 'technician' then
    perform public.recalc_community_reputation(
      coalesce(new.author_id, old.author_id)
    );
  end if;

  return coalesce(new, old);
end;
$function$;

drop trigger if exists community_comments_sync on public.community_comments;
create trigger community_comments_sync
  after insert or delete on public.community_comments
  for each row execute function public.sync_community_comment();

-- ---------------------------------------------------------------------------
-- 6. Author display
-- ---------------------------------------------------------------------------
--
-- Same problem `job_conversations` had: `profiles` is owner-readable, so a
-- plain join leaves every author's name null. This resolves the name, avatar,
-- role, tier and community standing in one SECURITY DEFINER hop.
--
-- It exposes only what already appears beside a public answer. Phone, email
-- and address are not in it and must not be added.

create or replace function public.community_author(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $function$
  select jsonb_build_object(
    'id',          p.id,
    'full_name',   p.full_name,
    'avatar_url',  p.avatar_url,
    'role',        p.role,
    'tier',        t.tier,
    'badge',       t.badge,
    'is_verified', coalesce(t.is_verified, false),
    'rating',      coalesce(t.rating, 0),
    'points',      coalesce(r.points, 0),
    'answers',     coalesce(r.answers, 0)
  )
  from public.profiles p
  left join public.technicians t on t.id = p.id
  left join public.community_reputation r on r.technician_id = p.id
  where p.id = p_id;
$function$;

grant execute on function public.community_author(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. The feed and the thread
-- ---------------------------------------------------------------------------
--
-- `security_invoker` on both, so the policies above decide what is visible
-- rather than the view's owner. Both are readable by every signed-in user,
-- which is what the select policies already say - the setting is here so a
-- later tightening of those policies is respected automatically.

create or replace view public.community_feed as
select
  p.id,
  p.title,
  p.body,
  p.topic,
  p.comment_count,
  p.last_activity_at,
  p.created_at,
  p.author_id,
  public.community_author(p.author_id) as author,
  (p.author_id = auth.uid())           as is_mine,
  -- Drives the "answered" chip, and it is the single most useful signal on
  -- the feed: an unanswered question is the one a technician should open.
  (p.comment_count > 0)                as is_answered,
  -- Total helpful votes across the thread, for the "Most Helpful" sort.
  coalesce((
    select sum(c.helpful_count) from public.community_comments c
    where c.post_id = p.id
  ), 0)                                as helpful_total
from public.community_posts p;

comment on view public.community_feed is
  'The Community tab: one row per question with its author and tallies.';

alter view public.community_feed set (security_invoker = on);
grant select on public.community_feed to authenticated;

create or replace view public.community_thread as
select
  c.id,
  c.post_id,
  c.body,
  c.author_role,
  c.helpful_count,
  c.created_at,
  c.author_id,
  public.community_author(c.author_id) as author,
  (c.author_id = auth.uid())           as is_mine,
  -- Whether the caller has already voted, so the button renders in the right
  -- state on first paint instead of flicking after a second request.
  exists (
    select 1 from public.community_votes v
    where v.comment_id = c.id and v.voter_id = auth.uid()
  )                                    as has_voted,
  -- Whether the caller is allowed to vote at all. Mirrors the insert policy,
  -- so the UI can hide the control rather than offer a button that fails.
  (
    c.author_role = 'technician'
    and c.author_id <> auth.uid()
    and public.profile_role(auth.uid()) = 'client'
  )                                    as can_vote
from public.community_comments c;

comment on view public.community_thread is
  'Answers on a post, with the author resolved and the caller''s own vote '
  'state folded in.';

alter view public.community_thread set (security_invoker = on);
grant select on public.community_thread to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Realtime
-- ---------------------------------------------------------------------------
--
-- Same conditional shape as `job_messages` in 20260907000013: added when the
-- publication exists, skipped with a notice when it does not, so a project
-- without realtime still applies this migration.

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'community_comments'
    ) then
      alter publication supabase_realtime add table public.community_comments;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'community_posts'
    ) then
      alter publication supabase_realtime add table public.community_posts;
    end if;
  end if;
exception when others then
  raise notice 'could not add community tables to supabase_realtime: %', sqlerrm;
end $$;
