-- SUGO: actually hide the assessment answer key
--
-- ## Why this migration exists
--
-- 20260906000001 tried to hide `assessment_questions.correct_choice_index`
-- with:
--
--   revoke select (correct_choice_index) on assessment_questions from anon;
--
-- That silently did nothing, and a live check confirmed the answer key was
-- still readable with the anon key:
--
--   GET /rest/v1/assessment_questions?select=question,correct_choice_index
--   -> [{"question":"...","correct_choice_index":1}, ...]
--
-- The reason is a Postgres rule that is easy to miss: **a column-level REVOKE
-- has no effect while a table-level GRANT is still in place.** Supabase grants
-- table-wide SELECT to `anon` and `authenticated` on every new public table, so
-- the broad grant kept overriding the narrow revoke.
--
-- The correct order is the opposite: revoke the table-level grant first, then
-- grant back only the columns that are safe to read.
--
-- This matters because passing the quiz auto-sets `is_verified` and the tier.
-- A readable answer key is a direct path to a fraudulently verified elite
-- technician, which would poison Stage 1 of the matching engine.

-- 1. Remove the blanket grant that was masking the revoke.
revoke select on public.assessment_questions from anon;
revoke select on public.assessment_questions from authenticated;

-- 2. Grant back only the columns a quiz screen legitimately needs. Note that
--    `correct_choice_index` is absent, which is the entire point.
grant select (id, specialization, question, choices, created_at)
  on public.assessment_questions to anon;

grant select (id, specialization, question, choices, created_at)
  on public.assessment_questions to authenticated;

-- 3. `service_role` keeps full access. It bypasses RLS and column grants alike,
--    which is how the `submit-assessment` edge function reads the answer key to
--    score an attempt. Scoring therefore has to happen server-side - the client
--    literally cannot see what the right answers are, which is the property we
--    want.
grant select on public.assessment_questions to service_role;
