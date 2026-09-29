-- =============================================================================
-- SUGO: photos in job chat
-- =============================================================================
--
-- A client can now send a picture of the problem to the technician on their
-- job, and the technician can send one back ("this is the part that failed").
-- Until now `job_messages` carried text only.
--
-- ## Why a column and a bucket, rather than a URL in the body
--
-- Encoding the photo as a link inside `body` would have needed no migration,
-- and it was rejected: the push notification would read out a storage URL, the
-- conversation list preview would show one, and anyone with the link could
-- fetch the image because a public bucket has no idea who is on the job. A
-- nullable column plus a private bucket keeps the text clean and keeps the
-- photo behind the same two-people rule as the thread it belongs to.
--
-- ## What this changes about existing behaviour: nothing
--
-- `image_path` is nullable, so every existing row and every existing client
-- build keeps working. An older app simply never sets it and never reads it.
--
-- ## After applying this
--
--   supabase db push
--   supabase functions deploy notify-event     # photo push wording
--
-- The app degrades honestly until then: the attach button explains that photo
-- sharing is not set up on the server yet rather than failing on send.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. The column
-- ---------------------------------------------------------------------------

alter table public.job_messages
  add column if not exists image_path text;

comment on column public.job_messages.image_path is
  'Object path inside the private `chat-photos` bucket, as `<job_id>/<uuid>`. '
  'Null for a text-only message. The app resolves it to a signed URL; the '
  'bucket is never public.';

-- ---------------------------------------------------------------------------
-- 2. A message is now "text OR a photo"
-- ---------------------------------------------------------------------------
--
-- The original constraint required a non-empty body, which would refuse a
-- photo sent with no caption - the common case. The replacement keeps the
-- 2000-character ceiling and keeps empty-and-pointless messages out, but
-- accepts an empty body when there is an image attached.
--
-- The old constraint was created inline, so its name was generated. It is
-- looked up by its definition rather than guessed at, so this migration
-- applies cleanly whatever Postgres called it.

do $$
declare
  v_name text;
begin
  select conname into v_name
  from pg_constraint
  where conrelid = 'public.job_messages'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%length(trim(body))%'
    and conname <> 'job_messages_content_check';

  if v_name is not null then
    execute format(
      'alter table public.job_messages drop constraint %I', v_name
    );
  end if;
end $$;

alter table public.job_messages
  drop constraint if exists job_messages_content_check;

alter table public.job_messages
  add constraint job_messages_content_check check (
    length(body) <= 2000
    and (length(trim(body)) > 0 or image_path is not null)
  );

-- ---------------------------------------------------------------------------
-- 3. A photo cannot be swapped after it is sent
-- ---------------------------------------------------------------------------
--
-- Same reasoning as the body guard this extends: the chat log is evidence if
-- the work is disputed, so neither party may rewrite what was sent. Without
-- this line the existing update policy - which exists so a recipient can mark
-- a message read - would also allow repointing `image_path` at another file.

create or replace function public.guard_job_message_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  -- The service role has no auth.uid() and passes through.
  if auth.uid() is null then
    return new;
  end if;

  if new.body is distinct from old.body
     or new.image_path is distinct from old.image_path
     or new.sender_id is distinct from old.sender_id
     or new.job_id is distinct from old.job_id
     or new.created_at is distinct from old.created_at then
    raise exception 'A sent message cannot be edited';
  end if;

  -- Only the RECIPIENT marks a message read. Letting the sender set it would
  -- make every read receipt meaningless.
  if new.read_at is distinct from old.read_at and new.sender_id = auth.uid() then
    raise exception 'You cannot mark your own message as read';
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. The bucket
-- ---------------------------------------------------------------------------
--
-- PRIVATE, unlike `job-photos`. Job photos are attached to a posting that the
-- matcher shows to three shortlisted technicians, so they are effectively
-- semi-public already. A photo sent inside a conversation is between two
-- people, and the bucket enforces that rather than relying on an unguessable
-- URL.
--
-- 5 MB and image types only, matching the other picture buckets.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-photos',
  'chat-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- 5. Who may read and write a chat photo
-- ---------------------------------------------------------------------------
--
-- Exactly the people who may read the thread. The object path starts with the
-- job id (`<job_id>/<uuid>`), so the same `is_job_participant()` that guards
-- `job_messages` answers this too - which is the point: one rule, one place.
--
-- The uuid cast is wrapped, because `name` is arbitrary text supplied by the
-- caller. A malformed path must return false, not raise - an exception inside
-- a policy surfaces as a 500 rather than a clean refusal.

create or replace function public.can_access_chat_photo(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_job uuid;
begin
  begin
    v_job := (storage.foldername(p_name))[1]::uuid;
  exception when others then
    return false;
  end;

  if v_job is null then
    return false;
  end if;

  return public.is_job_participant(v_job);
end;
$function$;

comment on function public.can_access_chat_photo(text) is
  'True when the caller is the client or the assigned technician on the job '
  'whose id prefixes this storage object path. Used by the chat-photos '
  'storage policies so photos follow the same rule as the thread.';

grant execute on function public.can_access_chat_photo(text) to authenticated;

drop policy if exists "chat_photos_insert_participant" on storage.objects;
create policy "chat_photos_insert_participant"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat-photos'
    and public.can_access_chat_photo(name)
  );

drop policy if exists "chat_photos_select_participant" on storage.objects;
create policy "chat_photos_select_participant"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'chat-photos'
    and public.can_access_chat_photo(name)
  );

-- No update and no delete policy, for the same reason `job_messages` has no
-- delete policy: a photo sent about a paid job is part of the record, and
-- either party being able to erase their half of it is worse than a picture
-- somebody regrets.

-- ---------------------------------------------------------------------------
-- 6. The conversation list shows "Photo" rather than an empty line
-- ---------------------------------------------------------------------------
--
-- `last_message` is the preview under a name in the inbox. A photo with no
-- caption would leave it blank, which reads as a broken row.

create or replace view public.job_conversations as
select
  j.id                            as job_id,
  j.client_id,
  j.assigned_technician_id,
  j.device_type,
  j.problem_symptom,
  j.status                        as job_status,
  case when j.client_id = auth.uid()
       then j.assigned_technician_id else j.client_id end as counterpart_id,
  public.profile_display(
    case when j.client_id = auth.uid()
         then j.assigned_technician_id else j.client_id end
  )                               as counterpart,
  (
    select case
             when coalesce(trim(m.body), '') = '' and m.image_path is not null
               then '📷 Photo'
             else m.body
           end
    from public.job_messages m
    where m.job_id = j.id
    order by m.created_at desc, m.id desc limit 1
  )                               as last_message,
  (
    select m.created_at from public.job_messages m
    where m.job_id = j.id
    order by m.created_at desc, m.id desc limit 1
  )                               as last_message_at,
  (
    select count(*) from public.job_messages m
    where m.job_id = j.id
      and m.sender_id <> auth.uid()
      and m.read_at is null
  )                               as unread_count
from public.jobs j
where (j.client_id = auth.uid() or j.assigned_technician_id = auth.uid())
  and j.assigned_technician_id is not null;

alter view public.job_conversations set (security_invoker = on);

grant select on public.job_conversations to authenticated;
