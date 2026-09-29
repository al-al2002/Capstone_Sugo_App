/**
 * Scheduled cleanup of signups that were never finished.
 *
 * ```
 * POST /functions/v1/purge-abandoned-signups   (service-role auth, from pg_cron)
 * { "older_than_hours": 24, "dry_run": true }
 *
 * -> { candidates, deleted, skipped, dry_run, report: [...] }
 * ```
 *
 * ## Why a scheduled sweep as well as `cancel-registration`
 *
 * `cancel-registration` handles the person who deliberately backs out. It
 * cannot help with the far more common case: someone signs up, gets distracted
 * at the role selection screen, and closes the app forever. Nothing on the
 * client will ever run for that account again, so cleanup has to come from
 * outside.
 *
 * ## What it will and will not delete
 *
 * Deletes only rows from `incomplete_signups`, and only those older than the
 * grace period.
 *
 * That view was redefined in 20260907000001. It used to mean "an authenticated
 * account with no `profiles` row at all", because registration wrote nothing
 * until it finished. Mandatory ID verification reversed that: a profile is
 * created at sign-up so the flow can be resumed, so the view now means
 * `registration_status = 'incomplete'` - an account that never submitted its
 * ID and selfie. The same people, identified by a column instead of an absence.
 *
 * Accounts in `pending_review` are deliberately NOT in that view. Someone
 * waiting on a human reviewer has done everything asked of them, and sweeping
 * them because review took longer than the grace period would be the worst
 * possible bug in this function.
 *
 * It never force-deletes. `jobs`, `job_matches` and `job_outcomes` reference
 * profiles and technicians without `on delete cascade`, so an account with any
 * real activity makes Postgres raise a foreign-key violation. This function
 * catches that, counts it as skipped, and moves on. An account that somehow
 * both looks abandoned and has bookings is a bug worth investigating, not
 * something to bulldoze.
 *
 * **Run it with `dry_run: true` first.** The report lists exactly what would
 * go, which is also the thing to show a panel when asked "what stops this
 * deleting real users?".
 */
import { fail, json, preflight } from "../_shared/cors.ts";
import { isServiceRequest, readJson, serviceClient } from "../_shared/supabase.ts";

/**
 * How long an unfinished signup is left alone.
 *
 * Long enough that someone who starts on the bus and finishes at home is never
 * caught, short enough that abandoned rows do not pile up. Overridable per
 * call so a demo can use a small window without redeploying.
 */
const DEFAULT_GRACE_HOURS = 24;

/** Safety valve: never delete more than this in one run. */
const MAX_PER_RUN = 200;

interface PurgeRequest {
  older_than_hours?: number;
  dry_run?: boolean;
}

interface IncompleteRow {
  id: string;
  email: string | null;
  created_at: string;
  last_sign_in_at: string | null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Use POST", 405);

  // No human caller. Deleting accounts in bulk is not something a user session
  // should ever be able to trigger.
  if (!isServiceRequest(req)) return fail("Service role required", 403);

  try {
    const body = await readJson<PurgeRequest>(req);

    const graceHours = Math.max(
      1,
      body.older_than_hours ?? DEFAULT_GRACE_HOURS,
    );
    const dryRun = body.dry_run === true;

    const cutoff = new Date(Date.now() - graceHours * 3600_000).toISOString();

    const db = serviceClient();

    const { data: candidates, error } = await db
      .from("incomplete_signups")
      .select("id, email, created_at, last_sign_in_at")
      .lt("created_at", cutoff)
      .order("created_at", { ascending: true })
      .limit(MAX_PER_RUN)
      .returns<IncompleteRow[]>();

    if (error) {
      return fail("Could not list incomplete signups", 500, error.message);
    }

    const rows = candidates ?? [];

    if (rows.length === 0) {
      return json({
        candidates: 0,
        deleted: 0,
        skipped: 0,
        dry_run: dryRun,
        grace_hours: graceHours,
        report: [],
        message: "Nothing to clean up.",
      });
    }

    let deleted = 0;
    let skipped = 0;
    const report: Array<Record<string, unknown>> = [];

    for (const row of rows) {
      // With deferred writes there is no per-step trail to read, so the only
      // signal left is whether they ever came back after signing up.
      const stage = row.last_sign_in_at &&
          row.last_sign_in_at !== row.created_at
        ? "signed in again but never finished"
        : "never got past sign-up";

      if (dryRun) {
        report.push({ ...row, stage, action: "would delete" });
        continue;
      }

      const { error: deleteError } = await db.auth.admin.deleteUser(row.id);

      if (deleteError) {
        // Almost always the FK guard: this account has real activity after
        // all. Skip it rather than forcing, and surface it in the report.
        skipped += 1;
        report.push({
          ...row,
          stage,
          action: "skipped",
          reason: deleteError.message,
        });
        console.warn(`purge: skipped ${row.id} - ${deleteError.message}`);
        continue;
      }

      deleted += 1;
      report.push({ ...row, stage, action: "deleted" });
    }

    console.log(
      `purge-abandoned-signups: ${rows.length} candidates older than ` +
        `${graceHours}h, ${deleted} deleted, ${skipped} skipped` +
        (dryRun ? " (dry run)" : ""),
    );

    return json({
      candidates: rows.length,
      deleted,
      skipped,
      dry_run: dryRun,
      grace_hours: graceHours,
      report,
    });
  } catch (error) {
    return fail("Cleanup failed", 500, (error as Error).message);
  }
});
