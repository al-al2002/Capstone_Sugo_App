// Applies the two 2026-11-15 migrations to a stub schema in PGlite (real
// Postgres in WASM) and checks the badge rules against real SQL.
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { randomUUID as uuid } from "node:crypto";

const MIG = process.argv[2];
const db = new PGlite();
const q = (sql, params = []) => db.query(sql, params);
const one = async (sql, params = []) => (await q(sql, params)).rows[0];

let failures = 0;
function check(name, ok, detail = "") {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(66)} ${ok ? "" : detail}`);
}
async function raises(name, fn, needle) {
  try {
    await fn();
    check(name, false, "did not raise");
  } catch (e) {
    check(name, !needle || String(e.message).includes(needle), e.message);
  }
}
const as = (id) => db.exec(`select set_config('request.jwt.claim.sub', '${id ?? ""}', false)`);
const badge = async (id) => (await one("select badge from technicians where id = $1", [id])).badge;

// ------------------------------------------------------------------ schema
await db.exec(readFileSync("stub_schema.sql", "utf8"));
await db.exec(readFileSync(`${MIG}/20261115000001_job_technician_preferences.sql`, "utf8"));
// A job written under the old ladder, to prove it is carried across.
const legacyClient = uuid();
await q("insert into profiles(id, role) values ($1, 'client')", [legacyClient]);
const legacyJob = (await one(
  "insert into jobs(client_id, pref_min_trust) values ($1, 'certified_pro') returning id",
  [legacyClient],
)).id;
await db.exec(readFileSync(`${MIG}/20261115000002_progressive_trust_badge.sql`, "utf8"));
console.log("migrations applied\n");

// ---------------------------------------------------------------- fixtures
const admin = uuid();
await q("insert into profiles(id, role) values ($1, 'admin')", [admin]);
const client = uuid();
await q("insert into profiles(id, role) values ($1, 'client')", [client]);

async function tech({ email = true, identity = true, specs = [["smartphone", true]], tier = "verified" } = {}) {
  const id = uuid();
  await q("insert into profiles(id, role) values ($1, 'technician')", [id]);
  await q("insert into auth.users(id, email_confirmed_at) values ($1, $2)", [id, email ? new Date().toISOString() : null]);
  await q("insert into technicians(id, verification_tier) values ($1, $2)", [id, tier]);
  if (identity) await q("insert into identity_verifications(user_id, status) values ($1, 'approved')", [id]);
  for (const [device, verified] of specs) {
    await q(
      "insert into technician_specializations(technician_id, device_type, verified, skill_level) values ($1, $2, $3, $4)",
      [id, device, verified, verified ? "expert" : null],
    );
  }
  return id;
}

// N completed jobs, each with an accepted match (legacy: no timestamps) and
// an outcome. `ratings` are spread over the first jobs; the rest unrated.
async function history(id, { completed, ratings }) {
  const jobs = [];
  for (let i = 0; i < completed; i++) {
    const job = (await one(
      "insert into jobs(client_id, assigned_technician_id, status) values ($1, $2, 'completed') returning id",
      [client, id],
    )).id;
    await q("insert into job_matches(job_id, technician_id, status) values ($1, $2, 'accepted')", [job, id]);
    await q("insert into job_outcomes(job_id, technician_id, final_rating) values ($1, $2, $3)", [job, id, ratings[i] ?? null]);
    jobs.push(job);
  }
  return jobs;
}
async function declines(id, n) {
  for (let i = 0; i < n; i++) {
    const job = (await one("insert into jobs(client_id) values ($1) returning id", [client])).id;
    await q("insert into job_matches(job_id, technician_id, status) values ($1, $2, 'declined')", [job, id]);
  }
}
async function misses(id, n) {
  for (let i = 0; i < n; i++) {
    await q("insert into offer_misses(technician_id, job_id, offered_at, how) values ($1, $2, now() - interval '2 days', 'withdrawn')", [id, uuid()]);
  }
}
const evaluate = (id) => one("select public.evaluate_technician_badge($1) as level", [id]);
const metrics = async (id) => (await one("select public.technician_badge_metrics($1) as m", [id])).m;

// ------------------------------------------------- the pure ladder
{
  const L = async (...a) => (await one(
    "select public.trust_badge_level($1,$2,$3,$4,$5,$6,$7,$8) as l", a)).l;
  check("ladder: no identity -> no badge", (await L(false, true, 3, 99, 5, 1, 0, 0)) === null);
  check("ladder: unconfirmed email -> no badge", (await L(true, false, 3, 99, 5, 1, 0, 0)) === null);
  check("ladder: identity, no skill -> id_verified", (await L(true, true, 0, 99, 5, 1, 0, 0)) === "id_verified");
  check("ladder: brief case 52 / 4.6 / 93% / 0 / 7% -> community_trusted",
    (await L(true, true, 1, 52, 4.6, 0.93, 0, 0.07)) === "community_trusted");
  check("ladder: 88% response -> skill_verified", (await L(true, true, 1, 52, 4.6, 0.88, 0, 0.07)) === "skill_verified");
  check("ladder: exactly 10% cancellations -> not trusted (strict <)",
    (await L(true, true, 1, 52, 4.6, 0.93, 0, 0.10)) === "skill_verified");
  check("ladder: one dispute -> skill_verified", (await L(true, true, 1, 52, 4.6, 0.93, 1, 0)) === "skill_verified");
  check("ladder: 49 jobs -> skill_verified", (await L(true, true, 1, 49, 4.9, 1, 0, 0)) === "skill_verified");
}

// ------------------------------------- acceptance 1: real data, promoted
const t1 = await tech();
{
  const ratings = [...Array(30).fill(5), ...Array(20).fill(4)]; // mean 4.60
  await history(t1, { completed: 52, ratings });
  await declines(t1, 41);   // 52 + 41 = 93 answered in time
  await misses(t1, 7);      // 93 / 100 = 93%
  const level = (await evaluate(t1)).level;
  const m = await metrics(t1);
  check("acceptance 1: 52 jobs, 4.6, 93%, 0 disputes -> community_trusted",
    level === "community_trusted", JSON.stringify(m));
  check("metrics: completed 52", m.completed_jobs === 52, m.completed_jobs);
  check("metrics: avg rating 4.60", Number(m.avg_rating) === 4.6, m.avg_rating);
  check("metrics: response rate 0.93", Number(m.response_rate) === 0.93, m.response_rate);
  check("stored on technicians.badge", (await badge(t1)) === "community_trusted");
}

// ---------------- acceptance 2: missed offers drop it to 88%, automatically
{
  // Four offers the client withdraws after the 24 h window - through the
  // real trigger, so offer_misses AND the re-evaluation fire on their own.
  for (let i = 0; i < 4; i++) {
    const job = (await one("insert into jobs(client_id) values ($1) returning id", [client])).id;
    const match = (await one(
      "insert into job_matches(job_id, technician_id, status) values ($1, $2, 'shortlisted') returning id",
      [job, t1],
    )).id;
    await q("update job_matches set status = 'offered' where id = $1", [match]);
    await q("update job_matches set offered_at = now() - interval '25 hours' where id = $1", [match]);
    await q("update job_matches set status = 'shortlisted' where id = $1", [match]); // withdrawn
  }
  const m = await metrics(t1);
  check("withdrawals past the window are logged as misses",
    (await one("select count(*)::int as n from offer_misses where technician_id = $1", [t1])).n === 11);
  check("acceptance 2: 93/106 = 88% -> reverts to skill_verified by itself",
    (await badge(t1)) === "skill_verified", `${m.response_rate} ${await badge(t1)}`);
}

// ------------------------------------------------------------- offer clock
{
  const t = await tech();
  const job = (await one("insert into jobs(client_id) values ($1) returning id", [client])).id;
  const match = (await one(
    "insert into job_matches(job_id, technician_id) values ($1, $2) returning id", [job, t])).id;
  await q("update job_matches set status = 'offered' where id = $1", [match]);
  const offered = await one("select offered_at, responded_at from job_matches where id = $1", [match]);
  check("offer clock: becoming offered stamps offered_at", offered.offered_at !== null && offered.responded_at === null);
  await q("update job_matches set status = 'shortlisted' where id = $1", [match]);
  check("offer clock: withdrawn within the window is NOT a miss",
    (await one("select count(*)::int as n from offer_misses where technician_id = $1", [t])).n === 0);
  await q("update job_matches set status = 'offered' where id = $1", [match]);
  await q("update job_matches set status = 'accepted' where id = $1", [match]);
  const answered = await one("select responded_at from job_matches where id = $1", [match]);
  check("offer clock: an answer stamps responded_at", answered.responded_at !== null);

  const job2 = (await one("insert into jobs(client_id) values ($1) returning id", [client])).id;
  const m2 = (await one(
    "insert into job_matches(job_id, technician_id, status) values ($1, $2, 'shortlisted') returning id", [job2, t])).id;
  await q("update job_matches set status = 'offered' where id = $1", [m2]);
  await q("update job_matches set offered_at = now() - interval '30 hours' where id = $1", [m2]);
  await q("delete from job_matches where id = $1", [m2]); // re-match / edit post
  check("offer clock: an ignored offer deleted by a re-match is still a miss",
    (await one("select count(*)::int as n from offer_misses where technician_id = $1 and how = 'cleared'", [t])).n === 1);

  const job3 = (await one("insert into jobs(client_id) values ($1) returning id", [client])).id;
  const m3 = (await one(
    "insert into job_matches(job_id, technician_id, status) values ($1, $2, 'shortlisted') returning id", [job3, t])).id;
  await q("update job_matches set status = 'offered' where id = $1", [m3]);
  await q("update job_matches set offered_at = now() - interval '26 hours' where id = $1", [m3]);
  await q("update job_matches set status = 'declined' where id = $1", [m3]);
  const m = await metrics(t);
  check("offer clock: an answer after 24 h counts against the rate",
    m.offers_counted === 3 && m.offers_answered_in_time === 1, JSON.stringify(m));
}

// ----------------------- acceptance 3: dispute remedy drops exactly one level
{
  // Skill verified (phone only) -> loses phone -> ID verified.
  const sv = await tech({ specs: [["smartphone", true], ["tablet", true]] });
  await evaluate(sv);
  const job = (await one(
    "insert into jobs(client_id, assigned_technician_id, status) values ($1, $2, 'completed') returning id", [client, sv])).id;
  const d = (await one(
    "insert into job_disputes(job_id, raised_by, raised_by_role) values ($1, $2, 'client') returning id", [job, client])).id;
  await one("select public.resolve_job_dispute($1, 'resolved', 'Screen failed again', $2, 'upheld', 'skill_deverification', 'phone_tablet')", [d, admin]);
  check("acceptance 3a: skill_verified -> id_verified for that specialisation",
    (await badge(sv)) === "id_verified", await badge(sv));
  const rows = await one("select bool_or(verified) as any_verified from technician_specializations where technician_id = $1", [sv]);
  check("the phone/tablet rows lost verified", rows.any_verified === false);

  // Other specialisations survive the remedy.
  const two = await tech({ specs: [["smartphone", true], ["laptop", true]] });
  const job2 = (await one(
    "insert into jobs(client_id, assigned_technician_id, status) values ($1, $2, 'completed') returning id", [client, two])).id;
  const d2 = (await one(
    "insert into job_disputes(job_id, raised_by, raised_by_role) values ($1, $2, 'client') returning id", [job2, client])).id;
  await one("select public.resolve_job_dispute($1, 'resolved', 'Screen failed again', $2, 'upheld', 'skill_deverification', 'phone_tablet')", [d2, admin]);
  const specs = await one("select public.skill_verified_specializations($1) as s", [two]);
  check("a remedy on phone/tablet leaves computer verified",
    JSON.stringify(specs.s) === JSON.stringify(["computer"]) && (await badge(two)) === "skill_verified",
    JSON.stringify(specs.s));

  // Community Trusted -> Skill Verified, skills untouched.
  const ct = await tech();
  await history(ct, { completed: 50, ratings: Array(50).fill(5) });
  await evaluate(ct);
  check("setup: second technician is community_trusted", (await badge(ct)) === "community_trusted");
  const job3 = (await one(
    "insert into jobs(client_id, assigned_technician_id, status) values ($1, $2, 'completed') returning id", [client, ct])).id;
  const d3 = (await one(
    "insert into job_disputes(job_id, raised_by, raised_by_role) values ($1, $2, 'client') returning id", [job3, client])).id;
  check("an OPEN client report already blocks community_trusted", (await badge(ct)) === "skill_verified");
  await one("select public.resolve_job_dispute($1, 'resolved', 'Overcharged, upheld', $2, 'upheld', 'skill_deverification', 'phone_tablet')", [d3, admin]);
  check("acceptance 3b: community_trusted -> skill_verified, one level only",
    (await badge(ct)) === "skill_verified", await badge(ct));
  check("...and the phone skill was NOT removed",
    (await one("select bool_and(verified) as v from technician_specializations where technician_id = $1", [ct])).v === true);

  await raises("a remedy on a dismissed report is refused", async () => {
    const j = (await one("insert into jobs(client_id, assigned_technician_id) values ($1, $2) returning id", [client, ct])).id;
    const x = (await one("insert into job_disputes(job_id, raised_by, raised_by_role) values ($1, $2, 'client') returning id", [j, client])).id;
    await one("select public.resolve_job_dispute($1, 'dismissed', 'Nothing wrong here', $2, null, 'skill_deverification', 'computer')", [x, admin]);
  }, "upheld");
}

// --------------------------------------- de-verification sticks, retake works
{
  const t = await tech({ specs: [["smartphone", false]] });
  await q("select public.record_assessment_result($1, 'mobile_repair', 95)", [t]);
  check("setup: passed assessment verifies", (await badge(t)) === "skill_verified");
  const job = (await one(
    "insert into jobs(client_id, assigned_technician_id, status) values ($1, $2, 'completed') returning id", [client, t])).id;
  const d = (await one(
    "insert into job_disputes(job_id, raised_by, raised_by_role) values ($1, $2, 'client') returning id", [job, client])).id;
  await one("select public.resolve_job_dispute($1, 'resolved', 'Upheld complaint', $2, 'upheld', 'skill_deverification', 'phone_tablet')", [d, admin]);

  // Delete and re-add the specialisation, as the technician.
  await as(t);
  await q("delete from technician_specializations where technician_id = $1", [t]);
  await q("insert into technician_specializations(technician_id, device_type) values ($1, 'tablet')", [t]);
  await as(null);
  check("re-adding after de-verification does NOT inherit the old pass",
    (await one("select verified from technician_specializations where technician_id = $1", [t])).verified === false);

  await q("update technician_assessment_results set taken_at = now() - interval '8 days' where technician_id = $1", [t]);
  const retake = await one("select public.record_assessment_result($1, 'mobile_repair', 85) as r", [t]);
  check("the technician may retake the assessment and earn it back",
    retake.r.passed === true && (await badge(t)) === "skill_verified", JSON.stringify(retake.r));
}

// ------------------------------------------------------------------- guard
{
  const t = await tech({ specs: [["laptop", true]] });
  await evaluate(t);
  await as(t);
  let ok = true;
  try {
    await q("delete from technician_specializations where technician_id = $1", [t]);
  } catch (e) {
    ok = false;
    console.log("   ", e.message);
  }
  await as(null);
  check("guard: a technician's own action may still move their badge", ok && (await badge(t)) === "id_verified");
  await as(t);
  await raises("guard: a technician cannot write their own badge", () =>
    q("update technicians set badge = 'community_trusted' where id = $1", [t]), "cannot change their own badge");
  await as(null);
}

// ------------------------------------------------------------ certificates
{
  const t = await tech({ specs: [["desktop", false], ["laptop", false]] });
  const doc = (await one(
    "insert into technician_verification_documents(technician_id, doc_type) values ($1, 'certificate') returning id", [t])).id;
  const r = await one("select public.review_verification_document($1, true, $2, null, 'pc_building') as r", [doc, admin]);
  check("a certificate proving PC Building verifies the desktop row only",
    r.r.specializations_verified === 1 && (await badge(t)) === "skill_verified", JSON.stringify(r.r));
  await raises("an NBI clearance cannot prove a specialisation", async () => {
    const nbi = (await one(
      "insert into technician_verification_documents(technician_id, doc_type) values ($1, 'nbi_clearance') returning id", [t])).id;
    await one("select public.review_verification_document($1, true, $2, null, 'computer')", [nbi, admin]);
  }, "Only a certificate");
}

// ----------------------------------------------------------- baseline rules
{
  const noEmail = await tech({ email: false });
  check("no confirmed email -> no badge", (await evaluate(noEmail)).level === null);
  const noSkill = await tech({ specs: [["smartphone", false]] });
  check("declared but unproven -> id_verified", (await evaluate(noSkill)).level === "id_verified");
}

// -------------------------------------------------- the preference ladder
{
  check("an old certified_pro preference became community_trusted",
    (await one("select pref_min_trust from jobs where id = $1", [legacyJob])).pref_min_trust === "community_trusted");
  await raises("certified_pro can no longer be stored", () =>
    q("insert into jobs(client_id, pref_min_trust) values ($1, 'certified_pro')", [client]), "jobs_pref_min_trust_check");
  await raises("technicians.badge only holds the three levels", () =>
    q("update technicians set badge = 'Top Rated' where id = $1", [t1]), "technicians_badge_level");
}

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
