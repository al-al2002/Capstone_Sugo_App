-- SUGO: give every message its own instant
--
-- ## What was wrong
--
-- `job_messages.created_at` defaulted to `now()`, which in Postgres is the
-- TRANSACTION start time, not the moment of the insert. Two messages written
-- in one transaction therefore share a timestamp to the microsecond:
--
--   first  @ 2026-09-08 11:14:16.71307+00
--   second @ 2026-09-08 11:14:16.71307+00
--
-- `order by created_at` then has no defined answer between them, so a thread
-- could render out of order and "last message" in the conversation list could
-- pick either one. Caught while testing the chat rules, where both sides of a
-- conversation were inserted in a single transaction and the preview showed
-- the older message.
--
-- ## Why it did not bite in the app
--
-- Each send is its own statement from the client, so each is its own implicit
-- transaction and gets a distinct `now()`. The bug is only reachable from a
-- batch insert - a seed script, a test fixture, or any future feature that
-- writes two messages at once.
--
-- That is exactly the kind of latent fault worth closing while it is cheap: it
-- would surface later as "messages sometimes appear in the wrong order", which
-- is near-impossible to reproduce on demand.
--
-- ## The fix
--
-- `clock_timestamp()` reads the actual wall clock at the moment of the insert,
-- so two rows in one transaction get different values. Plus a deterministic
-- tiebreaker on `id`, so even identical timestamps produce a stable order
-- rather than an arbitrary one.

alter table public.job_messages
  alter column created_at set default clock_timestamp();

comment on column public.job_messages.created_at is
  'clock_timestamp(), not now(): now() is the transaction start time, so two '
  'messages inserted together would share a timestamp and order arbitrarily.';

-- Ordering index gains the tiebreaker so the sorted read stays index-only.
drop index if exists idx_job_messages_job;
create index if not exists idx_job_messages_job
  on public.job_messages (job_id, created_at, id);

-- The conversation list picks the newest message deterministically.
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
    select m.body from public.job_messages m
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
