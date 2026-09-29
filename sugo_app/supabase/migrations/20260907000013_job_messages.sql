-- SUGO: in-app chat between a client and the technician on their job
--
-- Chat is scoped to a JOB, not to a pair of people. That is the whole design
-- decision and everything else follows from it:
--
--   * A client who books the same technician twice gets two conversations,
--     one per job, so "what did we agree about the aircon?" is not buried in
--     messages about the laptop.
--   * Permission is derivable. There is no separate participants table - the
--     job already records who the client is and who the technician is, so RLS
--     can answer "may this person read this thread?" from the job row alone.
--   * A thread ends when the job does. Nobody keeps a channel open to a
--     stranger they hired once.

-- ---------------------------------------------------------------------------
-- 1. The messages
-- ---------------------------------------------------------------------------

create table if not exists public.job_messages (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,

  body text not null check (length(trim(body)) > 0 and length(body) <= 2000),

  -- Null until the other side opens the thread. Per-message rather than a
  -- single "last read" pointer per conversation: it costs one column and makes
  -- the unread count a plain filter instead of a join against a cursor table.
  read_at timestamptz,

  created_at timestamptz not null default now()
);

comment on table public.job_messages is
  'Chat between the client and the assigned technician, scoped to one job. '
  'Participation is derived from the jobs row, so there is no participants '
  'table to keep in step.';

-- The only query the thread screen makes: this job, oldest first.
create index if not exists idx_job_messages_job
  on public.job_messages (job_id, created_at);

-- Unread badges: "messages on my jobs that I did not send and have not read".
create index if not exists idx_job_messages_unread
  on public.job_messages (job_id, sender_id)
  where read_at is null;

-- ---------------------------------------------------------------------------
-- 2. Who may see a thread
-- ---------------------------------------------------------------------------
--
-- Exactly two people: the client who posted the job, and the technician
-- assigned to it. Both sides are checked against `jobs` rather than trusted
-- from the message row.
--
-- WHY ASSIGNMENT AND NOT AN OFFER. A technician who has merely been *offered*
-- a job cannot chat. Three technicians receive every offer, and opening a
-- channel to all three would let two strangers message a client about a job
-- they will never do - and would leak that the client is shopping around. The
-- thread opens when one of them accepts and `assigned_technician_id` is set.

create or replace function public.is_job_participant(p_job_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1 from public.jobs j
    where j.id = p_job_id
      and (j.client_id = auth.uid() or j.assigned_technician_id = auth.uid())
  );
$function$;

comment on function public.is_job_participant(uuid) is
  'True when the caller is the client or the assigned technician on this job. '
  'SECURITY DEFINER so the check can read `jobs` rows the caller''s own RLS '
  'would hide - a technician cannot select a job until assigned.';

alter table public.job_messages enable row level security;

drop policy if exists "job_messages_select_participant" on public.job_messages;
create policy "job_messages_select_participant"
  on public.job_messages for select to authenticated
  using (public.is_job_participant(job_id));

-- The `sender_id = auth.uid()` term is what stops a participant writing a
-- message that appears to come from the other person.
drop policy if exists "job_messages_insert_participant" on public.job_messages;
create policy "job_messages_insert_participant"
  on public.job_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_job_participant(job_id)
  );

-- Update exists only so the recipient can mark a message read. The guard in
-- section 3 pins it to that one column, so this policy cannot be used to edit
-- what somebody said.
drop policy if exists "job_messages_update_participant" on public.job_messages;
create policy "job_messages_update_participant"
  on public.job_messages for update to authenticated
  using (public.is_job_participant(job_id));

-- No delete policy. A chat log about a paid job is evidence if the work is
-- disputed, and either party being able to erase their half of it is worse
-- than a message someone regrets.

-- ---------------------------------------------------------------------------
-- 3. A message cannot be rewritten after it is sent
-- ---------------------------------------------------------------------------
--
-- Same shape as every other guard in this schema: the row policy says *which*
-- row, this says *which columns*. Without it the update policy above would let
-- a participant rewrite the body of a message - including one the other person
-- sent - long after it was read.

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

drop trigger if exists job_messages_guard_update on public.job_messages;
create trigger job_messages_guard_update
  before update on public.job_messages
  for each row execute function public.guard_job_message_update();

-- ---------------------------------------------------------------------------
-- 4. Mark a thread read
-- ---------------------------------------------------------------------------
--
-- One statement instead of one update per message. Scoped to messages the
-- caller did NOT send, which is what the guard above requires anyway.

create or replace function public.mark_job_messages_read(p_job_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_count integer;
begin
  if not public.is_job_participant(p_job_id) then
    raise exception 'You are not part of this conversation';
  end if;

  update public.job_messages
  set read_at = now()
  where job_id = p_job_id
    and sender_id <> auth.uid()
    and read_at is null;

  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

grant execute on function public.mark_job_messages_read(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The conversation list
-- ---------------------------------------------------------------------------
--
-- What the Chat tab renders: one row per job the caller is part of, with the
-- other person resolved and the last message folded in.
--
-- `security_invoker` so the view runs with the caller's own permissions and
-- the `jobs` policies decide which rows they see. A definer view here would
-- hand every conversation on the platform to anyone who queried it.
--
-- The counterpart's name comes from `profiles`, which is readable only by its
-- owner - so the join is done in a SECURITY DEFINER helper rather than
-- inline. `counterpart_name` would otherwise be null for everybody.

create or replace function public.profile_display(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $function$
  select jsonb_build_object(
    'id', p.id,
    'full_name', p.full_name,
    'avatar_url', p.avatar_url
  )
  from public.profiles p where p.id = p_id;
$function$;

grant execute on function public.profile_display(uuid) to authenticated;

create or replace view public.job_conversations as
select
  j.id                            as job_id,
  j.client_id,
  j.assigned_technician_id,
  j.device_type,
  j.problem_symptom,
  j.status                        as job_status,
  -- The other person, from the caller's point of view.
  case when j.client_id = auth.uid()
       then j.assigned_technician_id else j.client_id end as counterpart_id,
  public.profile_display(
    case when j.client_id = auth.uid()
         then j.assigned_technician_id else j.client_id end
  )                               as counterpart,
  (
    select m.body from public.job_messages m
    where m.job_id = j.id order by m.created_at desc limit 1
  )                               as last_message,
  (
    select m.created_at from public.job_messages m
    where m.job_id = j.id order by m.created_at desc limit 1
  )                               as last_message_at,
  (
    select count(*) from public.job_messages m
    where m.job_id = j.id
      and m.sender_id <> auth.uid()
      and m.read_at is null
  )                               as unread_count
from public.jobs j
where (j.client_id = auth.uid() or j.assigned_technician_id = auth.uid())
  -- A thread needs two people. An unassigned job has nobody to talk to.
  and j.assigned_technician_id is not null;

comment on view public.job_conversations is
  'One row per job the caller can chat about, with the counterpart resolved '
  'and the last message and unread count folded in.';

alter view public.job_conversations set (security_invoker = on);

grant select on public.job_conversations to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Realtime
-- ---------------------------------------------------------------------------
--
-- Same conditional shape as `job_tracking` in 20260906000007: added when the
-- publication exists, skipped with a notice when it does not, so a project
-- without realtime still applies this migration. The app polls as a fallback
-- either way.

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'job_messages'
     )
  then
    alter publication supabase_realtime add table public.job_messages;
  end if;
exception when others then
  raise notice 'could not add job_messages to supabase_realtime: %', sqlerrm;
end $$;
