-- SUGO: a rejection reason must not be stamped on approved credentials
--
-- ## The bug
--
-- `review_applicant()` fell back to the identity note for every document:
--
--   v_doc_notes := coalesce(nullif(trim(v_entry ->> 'notes'), ''), p_notes);
--
-- The intent was convenience - a reviewer rejecting several credentials for one
-- reason should not retype it per document. The effect was that the note landed
-- on the APPROVED ones too.
--
-- Caught by an end-to-end test: approving an ID and a certificate while
-- rejecting an NBI clearance left "Clearance is expired, please upload a
-- current one." attached to the approved certificate and the approved
-- portfolio. The technician would open their profile and read a rejection
-- reason on two credentials that were accepted.
--
-- ## The fix
--
-- The fallback applies to rejections only. An approval carries a note only when
-- the reviewer wrote one specifically for it, and otherwise carries none -
-- which is the honest answer, because there is nothing to explain.
--
-- Only the `v_doc_notes` assignment changes; the rest is unchanged from
-- 20260907000011.

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
  for v_entry in select * from jsonb_array_elements(coalesce(p_documents, '[]'::jsonb))
  loop
    v_decision := v_entry ->> 'decision';

    if v_decision not in ('approve', 'reject') then
      continue;  -- 'hold' or anything unrecognised: leave it for later.
    end if;

    v_doc_id := (v_entry ->> 'id')::uuid;

    -- The document must belong to the person being reviewed.
    select technician_id into v_owner
    from public.technician_verification_documents
    where id = v_doc_id;

    if v_owner is null or v_owner <> v_user_id then
      raise exception 'Document % does not belong to this applicant', v_doc_id;
    end if;

    -- A per-document note always wins. The identity note is borrowed only for
    -- a REJECTION, where the technician needs to be told what was wrong. An
    -- approval with no note of its own gets none: stamping the ID's rejection
    -- reason onto an accepted certificate is worse than saying nothing.
    v_doc_notes := nullif(trim(v_entry ->> 'notes'), '');

    if v_doc_notes is null and v_decision = 'reject' then
      v_doc_notes := p_notes;
    end if;

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
