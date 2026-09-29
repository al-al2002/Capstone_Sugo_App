-- SUGO: an unread badge for the Community tab
--
-- The tab had no signal at all, so the only way to learn that somebody had
-- answered your question was to go and look. For a feed whose whole value is
-- "a professional replied to you", that is the wrong way round.
--
-- ---------------------------------------------------------------------------
-- WHY "UNREAD" MEANS SOMETHING DIFFERENT PER ROLE
-- ---------------------------------------------------------------------------
--
-- A single count would have to pick one meaning, and the two roles do not
-- share one:
--
--   * A CLIENT wants to know that their question was answered. New questions
--     from other clients are not news to them - they cannot answer those.
--
--   * A TECHNICIAN wants to know there is something to answer. Replies on
--     somebody else's thread are not theirs to act on.
--
-- So the function branches on role and counts the thing that role can act on.
-- Both are gated on when the caller last opened the tab, which is what makes
-- it an *unread* count rather than a running total that never clears.
--
-- ---------------------------------------------------------------------------
-- WHY THE WATERMARK IS SERVER-SIDE
-- ---------------------------------------------------------------------------
--
-- The obvious cheap version is a timestamp in local storage. This project has
-- no local-storage package, and adding one to hold a single timestamp would
-- buy a dependency plus a per-device answer: the badge would reappear on a
-- reinstall and disagree between a phone and a tablet.
--
-- One row per user costs less and is correct everywhere.

-- ---------------------------------------------------------------------------
-- 1. The watermark
-- ---------------------------------------------------------------------------

create table if not exists public.community_last_seen (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  seen_at timestamptz not null default now()
);

comment on table public.community_last_seen is
  'When each user last opened the Community tab. One row per user; the badge '
  'counts activity newer than this.';

alter table public.community_last_seen enable row level security;

-- Own row only. There is no reason for anyone to know when somebody else last
-- read the feed, and it is the kind of presence data that is quietly
-- uncomfortable once it leaks.
drop policy if exists "community_last_seen_select_own" on public.community_last_seen;
create policy "community_last_seen_select_own"
  on public.community_last_seen for select to authenticated
  using (user_id = auth.uid());

-- Writes go through `mark_community_seen()` rather than a policy, so the
-- timestamp is always `now()` and can never be backdated to inflate a badge.

-- ---------------------------------------------------------------------------
-- 2. Marking it read
-- ---------------------------------------------------------------------------

create or replace function public.mark_community_seen()
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  insert into public.community_last_seen (user_id, seen_at)
  values (auth.uid(), now())
  on conflict (user_id) do update set seen_at = now();
end;
$function$;

comment on function public.mark_community_seen() is
  'Stamps the caller''s Community watermark to now(). Always now() - never a '
  'value supplied by the client.';

revoke all on function public.mark_community_seen() from public;
revoke all on function public.mark_community_seen() from anon;
grant execute on function public.mark_community_seen() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The count
-- ---------------------------------------------------------------------------

create or replace function public.community_unread_count()
returns integer
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_seen timestamptz;
  v_role text;
  v_count integer;
begin
  if auth.uid() is null then
    return 0;
  end if;

  select seen_at into v_seen
  from public.community_last_seen
  where user_id = auth.uid();

  -- A user who has never opened the tab gets a bounded window rather than the
  -- whole history. Counting every question ever posted would put a "94" on a
  -- brand-new account, which reads as a backlog rather than as news.
  v_seen := coalesce(v_seen, now() - interval '7 days');

  v_role := public.profile_role(auth.uid());

  if v_role = 'technician' then
    -- Questions posted since they last looked that nobody has answered.
    -- Answered ones are excluded because they are no longer work waiting.
    select count(*) into v_count
    from public.community_posts p
    where p.created_at > v_seen
      and p.comment_count = 0;
  else
    -- Answers on this client's own questions, written by somebody else.
    select count(*) into v_count
    from public.community_comments c
    join public.community_posts p on p.id = c.post_id
    where p.author_id = auth.uid()
      and c.author_id <> auth.uid()
      and c.created_at > v_seen;
  end if;

  -- Capped. Past a couple of dozen the exact number stops informing anything,
  -- and the UI renders "9+" anyway.
  return least(coalesce(v_count, 0), 99);
end;
$function$;

comment on function public.community_unread_count() is
  'Unread Community activity for the caller: new answers on their own '
  'questions for a client, new unanswered questions for a technician.';

revoke all on function public.community_unread_count() from public;
revoke all on function public.community_unread_count() from anon;
grant execute on function public.community_unread_count() to authenticated;

-- Supports both branches of the count.
create index if not exists idx_community_posts_created
  on public.community_posts (created_at desc);

create index if not exists idx_community_comments_created
  on public.community_comments (created_at desc);
