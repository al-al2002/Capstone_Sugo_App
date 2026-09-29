-- SUGO: review an applicant's ID and credentials in one decision
--
-- ## Why
--
-- Reviewing a technician meant two screens and two queues: the ID + selfie on
-- `/verifications/{id}`, and their certificates and clearances on a separate
-- `/documents` page. A reviewer had to approve the identity, remember there
-- were credentials attached, navigate away and find them.
--
-- The console now shows both on the review screen and takes one decision. This
-- function is what makes that decision atomic.
--
-- ## Why atomic matters here
--
-- Done as separate calls from PHP, a failure partway leaves an approved
-- identity - which activates the account - beside credentials nobody ruled on.
-- The technician goes live claiming a certificate that was never checked. One
-- plpgsql function runs in a single implicit transaction, so either the whole
-- review lands or none of it does.
--
-- ## Ordering is deliberate
--
-- The identity is decided FIRST, then the documents. `review_verification_
-- document()` only promotes a technician to `certified_pro` when their account
-- is already `active`, and it is the identity approval that activates it. The
-- other order would approve a certificate against a still-pending account and
-- silently skip the promotion.

create or replace function public.review_applicant(
  p_verification_id uuid,
  p_approved boolean,
  p_reviewer_id uuid default null,
  p_notes text default null,
  p_documents jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user_id uuid;
  v_identity jsonb;
  v_entry jsonb;
  v_doc_id uuid;
  v_decision text;
  v_doc_notes text;
  v_owner uuid;
  v_approved_docs integer := 0;
  v_rejected_docs integer := 0;
begin
  select user_id into v_user_id
  from public.identity_verifications
  where id = p_verification_id;

  if v_user_id is null then
    raise exception 'No such identity verification: %', p_verification_id;
  end if;

  -- 1. The identity. Holds the activation rules, the rejection-reason
  --    requirement, and the "approved mid-flow leaves the status alone" logic.
  v_identity := public.review_identity_verification(
    p_verification_id, p_approved, p_reviewer_id, p_notes
  );

  -- 2. The credentials, each with its own verdict.
  --
  --    A reviewer can approve an identity while rejecting one forged
  --    certificate, which is why this is a per-document list rather than a
  --    single flag. Anything omitted, or marked 'hold', is left pending.
  for v_entry in select * from jsonb_array_elements(coalesce(p_documents, '[]'::jsonb))
  loop
    v_decision := v_entry ->> 'decision';

    if v_decision not in ('approve', 'reject') then
      continue;  -- 'hold' or anything unrecognised: leave it for later.
    end if;

    v_doc_id := (v_entry ->> 'id')::uuid;

    -- The document must belong to the person being reviewed. Without this a
    -- crafted request could rule on someone else's credentials through a
    -- review it legitimately has access to.
    select technician_id into v_owner
    from public.technician_verification_documents
    where id = v_doc_id;

    if v_owner is null or v_owner <> v_user_id then
      raise exception 'Document % does not belong to this applicant', v_doc_id;
    end if;

    -- Falls back to the identity note so a reviewer who rejects everything
    -- with one reason does not have to retype it per document.
    v_doc_notes := coalesce(nullif(trim(v_entry ->> 'notes'), ''), p_notes);

    perform public.review_verification_document(
      v_doc_id, v_decision = 'approve', p_reviewer_id, v_doc_notes
    );

    if v_decision = 'approve' then
      v_approved_docs := v_approved_docs + 1;
    else
      v_rejected_docs := v_rejected_docs + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'user_id', v_user_id,
    'identity', v_identity,
    'documents_approved', v_approved_docs,
    'documents_rejected', v_rejected_docs
  );
end;
$function$;

revoke all on function public.review_applicant(uuid, boolean, uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.review_applicant(uuid, boolean, uuid, text, jsonb)
  to service_role;

-- ---------------------------------------------------------------------------
-- Credentials still need their own queue
-- ---------------------------------------------------------------------------
--
-- A technician can upload a certificate months after being approved, when
-- there is no pending identity review to attach it to. Those documents would
-- become unreviewable if the merged screen were the only path, so the
-- standalone `/documents` page stays - it just is not the main route any more.
--
-- This view is what that page should read: pending credentials whose owner has
-- no identity review outstanding, i.e. exactly the ones the merged screen will
-- never show.

create or replace view public.orphan_document_queue as
select
  d.id,
  d.technician_id,
  d.doc_type,
  d.file_url,
  d.caption,
  d.status,
  d.uploaded_at,
  p.full_name,
  p.registration_status
from public.technician_verification_documents d
join public.profiles p on p.id = d.technician_id
where d.status = 'pending'
  and not exists (
    select 1 from public.identity_verifications iv
    where iv.user_id = d.technician_id and iv.status = 'pending'
  );

comment on view public.orphan_document_queue is
  'Pending credentials with no identity review to merge into - typically '
  'uploaded after the account was approved. The merged review screen cannot '
  'show these, so the standalone credentials page still can.';

revoke all on public.orphan_document_queue from anon, authenticated;
grant select on public.orphan_document_queue to service_role;
