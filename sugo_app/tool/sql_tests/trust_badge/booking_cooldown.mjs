// Checks the book-and-cancel cooldown (20261117000004) in PGlite:
//   * 2+ cancels in a rolling hour pause booking for 2 minutes after the
//     latest one; fewer, older, or finished pauses do not;
//   * "Cancel request" (withdraw_technician_offer) logs the cancel and says
//     when booking is paused;
//   * a client can read only their own cancels, and ask only about
//     themselves.
//
//   node booking_cooldown.mjs ../../../supabase/migrations
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { randomUUID as uuid } from "node:crypto";

const MIG = process.argv[2];
const db = new PGlite();
const q = (sql, params = []) => db.query(sql, params);
let failures = 0;
const check = (name, ok, detail = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(62)} ${ok ? "" : detail}`);
};
const as = (id) =>
  db.exec(`select set_config('request.jwt.claim.sub', '${id ?? ""}', false)`);

/** Seconds from now until the pause ends, or null when not paused. */
const pausedFor = async (client) => {
  const r = await q(
    `select extract(epoch from (public.booking_cooldown_until($1) - now()))::float as s`,
    [client],
  );
  return r.rows[0].s;
};
/** Logs a cancel `minutesAgo` minutes in the past. */
const cancel = (client, minutesAgo, kind = "delete") =>
  q(
    `insert into booking_cancellations (client_id, job_id, kind, cancelled_at)
     values ($1, $2, $3, now() - make_interval(secs => $4))`,
    [client, uuid(), kind, minutesAgo * 60],
  );
const near = (a, b) => a !== null && Math.abs(a - b) < 5;

await db.exec(readFileSync("stub_schema.sql", "utf8"));
// What Supabase grants by default and the stub leaves out.
await db.exec(`
  grant usage on schema auth to authenticated;
  grant execute on function auth.uid() to authenticated;
`);
await db.exec(readFileSync(`${MIG}/20261117000004_booking_cooldown.sql`, "utf8"));

const newClient = async () => {
  const id = uuid();
  await q("insert into profiles(id, role) values ($1, 'client')", [id]);
  return id;
};

// ------------------------------------------------------------------ the rule
await as(null); // the service role, as job-response calls it

const fresh = await newClient();
check("no cancels: books freely", (await pausedFor(fresh)) === null);

const once = await newClient();
await cancel(once, 0);
check("one cancel: still books freely", (await pausedFor(once)) === null);

const twice = await newClient();
await cancel(twice, 20);
await cancel(twice, 0);
const s = await pausedFor(twice);
check("2nd cancel within the hour: paused ~120 s", near(s, 120), `got ${s}`);

const later = await newClient();
await cancel(later, 10);
await cancel(later, 1);
const l = await pausedFor(later);
check("pause counts from the LATEST cancel (~60 s left)", near(l, 60), `got ${l}`);

const over = await newClient();
await cancel(over, 30);
await cancel(over, 3);
check("2 minutes after the latest: books again", (await pausedFor(over)) === null);

const spread = await newClient();
await cancel(spread, 70);
await cancel(spread, 0);
check("first cancel over an hour ago: not paused", (await pausedFor(spread)) === null);

const third = await newClient();
await cancel(third, 40);
await cancel(third, 10);
check("third client: pause from the 2nd has ended", (await pausedFor(third)) === null);
await cancel(third, 0);
const t = await pausedFor(third);
check("a 3rd cancel in the hour starts a fresh 2 minutes", near(t, 120), `got ${t}`);

// -------------------------------------------------------- "Cancel request"
const client = await newClient();
const tech = uuid();
await q("insert into profiles(id, role) values ($1, 'technician')", [tech]);
await q("insert into technicians(id) values ($1)", [tech]);

const bookedJob = async () => {
  const job = (await q(
    "insert into jobs(client_id, status) values ($1, 'matched') returning id",
    [client],
  )).rows[0].id;
  await q(
    "insert into job_matches(job_id, technician_id, status) values ($1, $2, 'offered')",
    [job, tech],
  );
  return job;
};

await as(client);
const job1 = await bookedJob();
const w1 = (await q("select public.withdraw_technician_offer($1) as r", [job1])).rows[0].r;
const logged = (await q(
  "select kind, technician_id from booking_cancellations where job_id = $1",
  [job1],
)).rows;
check("withdraw logs one 'withdraw' row naming the technician",
  logged.length === 1 && logged[0].kind === "withdraw" && logged[0].technician_id === tech,
  JSON.stringify(logged));
check("1st withdraw: not paused", w1.booking_paused_until === null, JSON.stringify(w1));
const back = (await q("select status from job_matches where job_id = $1", [job1])).rows[0];
check("withdraw still returns the offer to the shortlist", back.status === "shortlisted");

const job2 = await bookedJob();
const w2 = (await q("select public.withdraw_technician_offer($1) as r", [job2])).rows[0].r;
check("2nd withdraw: answer says when booking resumes", w2.booking_paused_until !== null,
  JSON.stringify(w2));

// ------------------------------------------------------------ who may look
let refused = false;
try {
  await as(client);
  await q("select public.booking_cooldown_until($1)", [twice]);
} catch (e) {
  refused = e.code === "42501";
}
check("a client cannot ask about another client", refused);

await as(client);
await db.exec("set role authenticated");
const visible = (await q("select distinct client_id from booking_cancellations")).rows;
await db.exec("reset role");
check("RLS: a client reads only their own cancels",
  visible.length === 1 && visible[0].client_id === client, JSON.stringify(visible));

let blocked = false;
try {
  await db.exec("set role authenticated");
  await q("delete from booking_cancellations where client_id = $1", [client]);
} catch (e) {
  blocked = e.code === "42501";
} finally {
  await db.exec("reset role");
}
check("a client cannot erase their own record", blocked);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
