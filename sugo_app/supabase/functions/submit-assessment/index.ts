/**
 * Scores a technician's skills assessment.
 *
 * Two request shapes, because two flows call it.
 *
 * ```
 * // Per-track (current flow, 20260907000008)
 * { "track": "computer_repair", "answers": { "<question_id>": 1, ... } }
 * -> { score, passed, skill_level, attempt_number, track,
 *      specializations_verified, retake_available_at, ... }
 *
 * // Account-wide (older flow, kept working)
 * { "specialization": "appliance_repair", "answers": { ... } }
 * -> { score, passed, suggested_tier, is_verified, attempt_id, ... }
 * ```
 *
 * ## Why scoring cannot happen in Dart
 *
 * **The client cannot see the answers.** Migration 20260906000002 revokes
 * `correct_choice_index` from `anon` and `authenticated`, so the quiz screen
 * physically cannot mark its own paper. Only `service_role` reads that column.
 *
 * **The client cannot award itself a result.** `record_assessment_result()` is
 * service-role only, and the guard trigger from 20260905000002 blocks a
 * technician from writing their own `is_verified` or `tier`. The client
 * submits raw answers; the only thing it influences is which options it picked.
 *
 * ## What changed with mandatory ID verification
 *
 * This function used to set `is_verified = true` the moment a quiz was passed,
 * with a TODO noting that a human should confirm the ID first. That TODO is now
 * resolved: **passing an assessment no longer activates an account.** A quiz
 * measures competence, not identity, and identity is what `is_verified` admits
 * someone into the matching pool on the strength of. Activation moved to
 * `review_identity_verification()`, called by a reviewer.
 *
 * Passing still awards `skill_level` and marks specialisations `verified` -
 * a claim about a skill, not about a person, and safe to grant automatically.
 * Since 20260907000008 that applies to EVERY specialisation in the track, so
 * one sitting qualifies a technician for all the brands they declared in it.
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerId, readJson, serviceClient } from "../_shared/supabase.ts";

/**
 * Pass mark for a per-specialisation assessment.
 *
 * Mirrors `public.assessment_skill_level`, which is the authority - it is what
 * actually awards the level. Repeated here only to report the threshold back
 * to the UI. 70 is stricter than the account-wide quiz's 60 because a
 * per-brand claim is a narrower and more specific promise to a client.
 */
const SPECIALIZATION_PASS_MARK = 70;

/** Pass mark for the older account-wide quiz. Unchanged. */
const LEGACY_PASS_THRESHOLD = 60;

/** Score bands for the legacy path, matching the `technicians.tier` check. */
const TIER_BANDS: Array<{ min: number; tier: "elite" | "pro" | "standard" }> = [
  { min: 90, tier: "elite" },
  { min: 75, tier: "pro" },
  { min: 60, tier: "standard" },
];

interface SubmitRequest {
  /**
   * Current flow: the assessment track. One track covers several device types
   * and every brand within them, so a technician sits it once rather than once
   * per declared specialisation - see 20260907000008.
   *
   * The track name is also the question bank name, so it selects both.
   */
  track?: string;
  /** Legacy flow: the bank doubles as the specialisation name. */
  specialization?: string;
  /** question id -> chosen choice index */
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

/**
 * Marks a submission against a question bank.
 *
 * An unanswered question counts as wrong rather than being skipped, so the
 * denominator is always the full bank - a partial submission cannot inflate
 * the percentage by shrinking what it is divided by.
 */
function mark(
  questions: QuestionRow[],
  answers: Record<string, number>,
): { correctCount: number; score: number } {
  let correctCount = 0;
  for (const question of questions) {
    if (answers[question.id] === question.correct_choice_index) {
      correctCount += 1;
    }
  }
  return {
    correctCount,
    score: Math.round((correctCount / questions.length) * 100),
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  try {
    const uid = await callerId(req);
    if (!uid) return fail("Sign in required", 401);

    const body = await readJson<SubmitRequest>(req);
    const answers = body.answers ?? {};

    if (Object.keys(answers).length === 0) {
      return fail("No answers were submitted", 422);
    }

    const db = serviceClient();

    const bank = (body.track ?? body.specialization ?? "").trim();
    if (!bank) {
      return fail("A track is required", 422);
    }

    const { data: questions, error: questionError } = await db
      .from("assessment_questions")
      .select("id, correct_choice_index")
      .eq("specialization", bank)
      .returns<QuestionRow[]>();

    if (questionError) {
      return fail("Could not load the question bank", 500, questionError.message);
    }
    if (!questions || questions.length === 0) {
      return fail(`No questions exist for ${bank}`, 404);
    }

    const { correctCount, score } = mark(questions, answers);

    // ---------------------------------------------------------------------
    // Current flow: per-track
    // ---------------------------------------------------------------------
    if (body.track) {
      // Ownership is checked inside `record_assessment_result`, which refuses a
      // track the technician holds no specialisation in. Checking here too
      // would duplicate the rule; the function is the authority.
      const { data, error } = await db.rpc("record_assessment_result", {
        p_technician_id: uid,
        p_track: body.track,
        p_score: score,
      });

      if (error) {
        // 55000 is raised by the function for an active cooldown. Its message
        // carries the retake time and is meant for the technician.
        if (error.code === "55000") return fail(error.message, 429);
        return fail(error.message ?? "Could not record your attempt", 400);
      }

      const result = (data ?? {}) as Record<string, unknown>;

      console.log(
        `assessment ${uid} track=${body.track}: ` +
          `${correctCount}/${questions.length} = ${score}% ` +
          `passed=${result.passed} level=${result.skill_level ?? "none"} ` +
          `verified=${result.specializations_verified ?? 0} specialisations`,
      );

      return json({
        ...result,
        score,
        correct_count: correctCount,
        total_questions: questions.length,
        pass_threshold: SPECIALIZATION_PASS_MARK,
      });
    }

    // ---------------------------------------------------------------------
    // Legacy flow: account-wide quiz
    // ---------------------------------------------------------------------
    const { data: technician, error: techError } = await db
      .from("technicians")
      .select("id, is_verified")
      .eq("id", uid)
      .maybeSingle<{ id: string; is_verified: boolean }>();

    if (techError) {
      return fail("Could not load your technician record", 500, techError.message);
    }
    if (!technician) {
      return fail("Submit your ID before taking the assessment", 409);
    }

    const passed = score >= LEGACY_PASS_THRESHOLD;
    const suggestedTier = tierFor(score);

    const { data: attempt, error: attemptError } = await db
      .from("technician_assessments")
      .insert({
        technician_id: uid,
        specialization: bank,
        answers,
        score,
        total_questions: questions.length,
        passed,
        suggested_tier: suggestedTier,
      })
      .select("id")
      .single();

    if (attemptError) {
      return fail("Could not record your attempt", 500, attemptError.message);
    }

    // The tier and specialisation are recorded on a pass, because both
    // describe the work rather than the person. `is_verified` is deliberately
    // NOT set - see the note at the top of this file. An account reaches the
    // matching pool only when a reviewer approves its identity.
    if (passed && suggestedTier) {
      const { error: updateError } = await db
        .from("technicians")
        .update({ tier: suggestedTier, specialization: [bank] })
        .eq("id", uid);

      if (updateError) {
        return fail(
          "Scored your assessment but could not save the result",
          500,
          updateError.message,
        );
      }
    }

    console.log(
      `assessment ${uid} (legacy): ${correctCount}/${questions.length} = ` +
        `${score}% passed=${passed} tier=${suggestedTier ?? "none"}`,
    );

    return json({
      attempt_id: attempt.id,
      specialization: bank,
      score,
      correct_count: correctCount,
      total_questions: questions.length,
      passed,
      pass_threshold: LEGACY_PASS_THRESHOLD,
      suggested_tier: suggestedTier,
      // Reports the account's real state, which a passing quiz no longer
      // changes. The client shows "awaiting review" rather than "you are live".
      is_verified: technician.is_verified,
    });
  } catch (error) {
    return fail("Could not score your assessment", 500, (error as Error).message);
  }
});
