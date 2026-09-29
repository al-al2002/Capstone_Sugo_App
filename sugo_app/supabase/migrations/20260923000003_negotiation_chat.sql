-- =============================================================================
-- SUGO: messaging before the technician accepts
-- =============================================================================
--
-- ## What this changes, and why it is not the decision it looks like
--
-- `20260907000013_job_messages.sql` wrote this, and it was right at the time:
--
--   > WHY ASSIGNMENT AND NOT AN OFFER. A technician who has merely been
--   > *offered* a job cannot chat. Three technicians receive every offer, and
--   > opening a channel to all three would let two strangers message a client
--   > about a job they will never do - and would leak that the client is
--   > shopping around.
--
-- Every clause of that objection was about the *old* meaning of `offered`.
-- `20260916000002_offer_requires_client_selection.sql` then split that meaning
-- in two:
--
--   shortlisted  the engine ranked you. The client has not asked you.
--   offered      the client picked you and sent you this job.
--
-- So today there is exactly one `offered` technician per job, and the client
-- put them there on purpose. There are no three strangers, and nothing to leak
-- about shopping around - the shortlist never leaves `shortlisted`, which this
-- migration does not touch.
--
-- What that unlocks is the thing the whole request rests on: a budget is a
-- guess made by somebody who does not know what the repair costs. When
-- ₱800-1,500 will not cover the part, the technician's only options today are
-- to decline silently or accept work they will lose money on. One message -
-- "it needs a new panel, that is ₱2,400 fitted, is that workable?" - turns a
-- dead request into a booking or an informed no.
--
-- ## What is deliberately NOT changed
--
-- **`jobs` RLS stays exactly as it is.** `jobs_technician_select_assigned`
-- still hides an unassigned job, so the technician still cannot read the
-- client's identity, their address or their pin before accepting. They can
-- talk to the person; they cannot look them up. Everything they need to judge
-- the offer is already in `score_breakdown.job`, which is a snapshot with no
-- address and no name in it.
--
-- That is also why the technician's inbox does not list a pending negotiation:
-- the conversation list reads `jobs` under the caller's own RLS, and widening
-- that to make a row appear would hand over the client's row as well. The
-- technician reaches the thread from the offer card on their dashboard
-- instead, which is where they are already deciding.
--
-- **Access ends when the offer does.** A technician who declines - or one the
-- client passes over - moves to `declined`, and the predicate below stops
-- matching. They keep nothing. The client keeps the thread, because it is
-- their job and their record of what was agreed.
--
-- ## Scope note
--
-- This WIDENS a read boundary, so it is flagged plainly, as the frozen-schema
-- rule requires. No table and no column is added. One function is redefined
-- and one view is rebuilt.
--
--   supabase db push
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Who counts as a participant
-- ---------------------------------------------------------------------------

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
  )
  -- The technician the client has actually asked. `status = 'offered'` is the
  -- whole guard: `shortlisted` is not included, so a ranked-but-unasked
  -- technician has no more access than a stranger.
  or exists (
    select 1 from public.job_matches m
    where m.job_id = p_job_id
      and m.technician_id = auth.uid()
      and m.status = 'offered'
  );
$function$;

comment on function public.is_job_participant(uuid) is
  'True when the caller is the client, the assigned technician, or the '
  'technician the client has offered this job to (job_matches.status = '
  '''offered''). SECURITY DEFINER so the check can read rows the caller''s own '
  'RLS would hide. Governs job_messages, mark_job_messages_read and chat '
  'photo access. An offered technician loses it the moment the match becomes '
  'declined or the client chooses somebody else.';

-- The predicate above is evaluated per message row on a thread read, so it
-- gets an index rather than a sequential scan of the match table.
create index if not exists idx_job_matches_job_technician_status
  on public.job_matches (job_id, technician_id, status);

-- ---------------------------------------------------------------------------
-- 2. The client's conversation list shows a pending negotiation
-- ---------------------------------------------------------------------------
--
-- Unchanged for assigned jobs. What is new is the second `and` arm: a job with
-- no technician yet still appears once the offered technician and the client
-- have actually said something to each other.
--
-- "Once something is said" matters. Listing every pending request as an empty
-- thread would fill the inbox with conversations nobody started, and bury the
-- real ones. A request with no messages is a booking, and it is already on the
-- Bookings tab.
--
-- The technician side of this view is untouched for the reason given in the
-- header: it reads `jobs` as the caller, and an unassigned job is not theirs
-- to read.

create or replace view public.job_conversations as
select
  j.id                            as job_id,
  j.client_id,
  j.assigned_technician_id,
  j.device_type,
  j.problem_symptom,
  j.status                        as job_status,
  case when j.client_id = auth.uid()
       then coalesce(j.assigned_technician_id, o.technician_id)
       else j.client_id end       as counterpart_id,
  public.profile_display(
    case when j.client_id = auth.uid()
         then coalesce(j.assigned_technician_id, o.technician_id)
         else j.client_id end
  )                               as counterpart,
  -- A photo with no caption is not an empty line in the list.
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
  )                               as unread_count,
  -- Lets the client's inbox label the row honestly: this technician has not
  -- accepted yet, so the thread is a negotiation, not a booking.
  (j.assigned_technician_id is null) as is_pending_offer
from public.jobs j
left join lateral (
  select m.technician_id
  from public.job_matches m
  where m.job_id = j.id
    and m.status = 'offered'
  order by m.created_at desc
  limit 1
) o on true
where (
        j.client_id = auth.uid()
        or j.assigned_technician_id = auth.uid()
        or o.technician_id = auth.uid()
      )
  and (
        j.assigned_technician_id is not null
        or (
          o.technician_id is not null
          and exists (
            select 1 from public.job_messages m where m.job_id = j.id
          )
        )
      );

comment on view public.job_conversations is
  'One row per conversation the caller can see: every assigned job, plus a '
  'job whose offered technician and client have started negotiating. '
  'security_invoker, so `jobs` RLS still decides which rows exist - which is '
  'why a pending negotiation appears for the client and not for the offered '
  'technician, who reaches it from their offer card instead.';

alter view public.job_conversations set (security_invoker = on);

grant select on public.job_conversations to authenticated;
