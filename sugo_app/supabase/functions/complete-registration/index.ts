/**
 * The single write that turns a signup into an account.
 *
 * ```
 * POST /functions/v1/complete-registration
 * { "role": "client",
 *   "full_name": "...", "phone": "...",
 *   "id_document_url": "<uid>/id_123.jpg" }
 *
 * { "role": "technician", ...,
 *   "specialization": "appliance_repair",
 *   "answers": { "<question_id>": 1, ... } }
 *
 * -> client:     { completed: true, role, score: null }
 * -> pass:       { completed: true, role, score, tier, passed: true }
 * -> fail:       { completed: false, score, passed: false, ... }   // nothing written
 * ```
 *
 * ## Why everything happens here
 *
 * Nothing is written to the `public` schema during onboarding any more. The app
 * holds the role, the ID and the quiz answers in memory and posts them once.
 * That way an abandoned registration leaves no `profiles` row, no `technicians`
 * row and no assessment attempt - only the `auth.users` row Supabase creates at
 * sign-up, which `purge-abandoned-signups` sweeps later.
 *
 * ## Failing the quiz writes nothing at all
 *
 * A failed attempt returns the score and stops. It is not recorded, because
 * `technician_assessments.technician_id` references a `technicians` row that
 * deliberately does not exist yet. The person retries with no trace left
 * behind. This is a real trade-off: retry history is lost, which an admin
 * review queue would otherwise have wanted. It follows directly from the
 * requirement that an unfinished registration touches nothing.
 *
 * ## Atomicity
 *
 * A technician's registration spans three tables. Doing that as three calls
 * from here would leave the first two behind if the third failed - exactly the
 * partial state this design exists to prevent. So the writes are delegated to
 * `public.complete_registration()`, a plpgsql function that runs in one
 * implicit transaction: every row appears, or none does.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, readJson, serviceClient } from "../_shared/supabase.ts";

const PASS_THRESHOLD = 60;

const TIER_BANDS: Array<{ min: number; tier: "elite" | "pro" | "standard" }> = [
  { min: 90, tier: "elite" },
  { min: 75, tier: "pro" },
  { min: 60, tier: "standard" },
];

interface CompleteRequest {
  role?: "client" | "technician";
  full_name?: string;
  phone?: string;
  id_document_url?: string;
  specialization?: string;
  answers?: Record<string, number>;
}

interface QuestionRow {
  id: string;
  correct_choice_index: number;
}

function tierFor(score: number): "elite" | "pro" | "standard" | null {
  for (const band of TIER_BANDS) {
    if (score >= band.min) return band.tier;
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const body = await readJson<CompleteRequest>(req);
    const role = body.role;
    const idDocumentUrl = body.id_document_url?.trim();

    if (role !== "client" && role !== "technician") {
      return fail("A role is required", 422);
    }
    if (!idDocumentUrl) {
      return fail("An identity document is required", 422);
    }

    // The uploaded object must live in the caller's own folder. Storage RLS
    // already enforces this on write; re-checking here stops a crafted request
    // from pointing a profile at someone else's document.
    if (!idDocumentUrl.startsWith(`${uid}/`)) {
      return fail("That document does not belong to you", 403);
    }

    const db = serviceClient();

    // ------------------------------------------------------------- client
    if (role === "client") {
      const { error } = await db.rpc("complete_registration", {
        p_user_id: uid,
        p_role: "client",
        p_full_name: body.full_name ?? null,
        p_phone: body.phone ?? null,
        p_id_document_url: idDocumentUrl,
      });

      if (error) {
        return fail("Could not finish your registration", 500, error.message);
      }

      console.log(`complete-registration: client ${uid} created`);
      return json({ completed: true, role: "client", passed: true });
    }

    // --------------------------------------------------------- technician
    const specialization = body.specialization?.trim();
    const answers = body.answers ?? {};

    if (!specialization) return fail("A specialisation is required", 422);
    if (Object.keys(answers).length === 0) {
      return fail("No assessment answers were submitted", 422);
    }

    const { data: questions, error: questionError } = await db
      .from("assessment_questions")
      .select("id, correct_choice_index")
      .eq("specialization", specialization)
      .returns<QuestionRow[]>();

    if (questionError) {
      return fail("Could not load the question bank", 500, questionError.message);
    }
    if (!questions || questions.length === 0) {
      return fail(`No questions exist for ${specialization}`, 404);
    }

    let correctCount = 0;
    for (const question of questions) {
      // Unanswered counts as wrong, so the denominator is always the full bank
      // and a partial submission cannot inflate the percentage.
      if (answers[question.id] === question.correct_choice_index) {
        correctCount += 1;
      }
    }

    const totalQuestions = questions.length;
    const score = Math.round((correctCount / totalQuestions) * 100);
    const passed = score >= PASS_THRESHOLD;
    const tier = tierFor(score);

    if (!passed || !tier) {
      // Nothing is written. They retry from the quiz screen with the answers
      // still held client-side.
      console.log(
        `complete-registration: ${uid} scored ${score}%, below ${PASS_THRESHOLD}% - nothing written`,
      );
      return json({
        completed: false,
        role: "technician",
        passed: false,
        score,
        correct_count: correctCount,
        total_questions: totalQuestions,
        pass_threshold: PASS_THRESHOLD,
        suggested_tier: null,
      });
    }

    // TODO(production): replace this auto-approval with an admin review queue.
    // A human should confirm the submitted ID is genuine before the account is
    // created as verified. Auto-approving is acceptable only while testing the
    // capstone flow end to end.
    const { error: rpcError } = await db.rpc("complete_registration", {
      p_user_id: uid,
      p_role: "technician",
      p_full_name: body.full_name ?? null,
      p_phone: body.phone ?? null,
      p_id_document_url: idDocumentUrl,
      p_specialization: specialization,
      p_answers: answers,
      p_score: score,
      p_total_questions: totalQuestions,
      p_tier: tier,
    });

    if (rpcError) {
      return fail("Could not finish your registration", 500, rpcError.message);
    }

    console.log(
      `complete-registration: technician ${uid} created at ${tier} (${score}%)`,
    );

    return json({
      completed: true,
      role: "technician",
      passed: true,
      score,
      correct_count: correctCount,
      total_questions: totalQuestions,
      pass_threshold: PASS_THRESHOLD,
      suggested_tier: tier,
    });
  } catch (error) {
    return fail(
      "Could not finish your registration",
      500,
      (error as Error).message,
    );
  }
});
