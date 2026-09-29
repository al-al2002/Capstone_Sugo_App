-- =============================================================================
-- SUGO: a photo on a community question
-- =============================================================================
--
-- "My laptop makes this noise" is a hard question to answer in words, and a
-- technician reading the feed is being asked to diagnose from a description
-- written by somebody who does not know the vocabulary. One picture removes
-- most of that.
--
-- Optional, and one per question: a feed of galleries scrolls badly, and the
-- second photo of the same fault adds far less than the first.
--
-- ## Why this bucket is public-read and `chat-photos` is not
--
-- A community question is posted to a feed every signed-in user can already
-- read, so the photo is not private - it is published, by the person posting
-- it. That matches `job-photos`, which is also public, and it keeps the feed
-- fast: a public URL renders straight from the CDN, while a private object
-- needs a signed URL minted per image per viewer.
--
-- A chat photo is the opposite - two people, one job - which is why that
-- bucket is private and gated by `is_job_participant`.
--
-- Uploads are still restricted: the path must start with the uploader's own
-- id, so nobody can write into somebody else's folder.
--
-- ## After applying this
--
--   supabase db push
--
-- Nothing else. The app reads `image_path` defensively, so an older build and
-- a newer database coexist.
-- =============================================================================

alter table public.community_posts
  add column if not exists image_path text;

comment on column public.community_posts.image_path is
  'Object path inside the public `community-photos` bucket, as '
  '`<author_id>/<file>`. Null for a question with no picture.';

-- ---------------------------------------------------------------------------
-- The bucket
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'community-photos',
  'community-photos',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Anyone may look at a picture attached to a public question.
drop policy if exists "community_photos_public_read" on storage.objects;
create policy "community_photos_public_read"
  on storage.objects for select
  using (bucket_id = 'community-photos');

-- Writing is confined to the author's own folder, which is what stops one
-- user replacing another's picture.
drop policy if exists "community_photos_insert_own_folder" on storage.objects;
create policy "community_photos_insert_own_folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'community-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "community_photos_update_own_folder" on storage.objects;
create policy "community_photos_update_own_folder"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'community-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Delete is allowed here, unlike chat photos: a question is the author's own
-- and they may take it down. `deletePost` already removes the row.
drop policy if exists "community_photos_delete_own_folder" on storage.objects;
create policy "community_photos_delete_own_folder"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'community-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- The feed carries it
-- ---------------------------------------------------------------------------
--
-- Same columns as before plus `image_path`, appended at the end so a client
-- that does not know about it is unaffected.

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
  ), 0)                                as helpful_total,
  p.image_path                         as image_path
from public.community_posts p;

alter view public.community_feed set (security_invoker = on);
grant select on public.community_feed to authenticated;
