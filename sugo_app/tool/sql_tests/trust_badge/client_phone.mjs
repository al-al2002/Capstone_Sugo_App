// Checks `job_client_phone` (20261117000001) in PGlite: only the technician
// assigned to a confirmed / in-progress job gets the client's phone.
//
//   node client_phone.mjs ../../../supabase/migrations
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { randomUUID as uuid } from "node:crypto";

const MIG = process.argv[2];
const db = new PGlite();
const q = (sql, params = []) => db.query(sql, params);
let failures = 0;
const check = (name, ok, detail = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(58)} ${ok ? "" : detail}`);
};
const as = (id) => db.exec(`select set_config('request.jwt.claim.sub', '${id ?? ""}', false)`);
const phoneFor = async (job) =>
  (await q("select public.job_client_phone($1) as p", [job])).rows[0].p;

await db.exec(readFileSync("stub_schema.sql", "utf8"));
await db.exec(readFileSync(`${MIG}/20261117000001_client_phone_for_assigned_technician.sql`, "utf8"));

const client = uuid();
const tech = uuid();
const other = uuid();
await q("insert into profiles(id, role, phone) values ($1, 'client', '09171234567')", [client]);
for (const id of [tech, other]) {
  await q("insert into profiles(id, role) values ($1, 'technician')", [id]);
  await q("insert into technicians(id) values ($1)", [id]);
}
const job = (status, assigned) =>
  q("insert into jobs(client_id, assigned_technician_id, status) values ($1, $2, $3) returning id",
    [client, assigned, status]).then((r) => r.rows[0].id);

const active = await job("in_progress", tech);
const confirmed = await job("confirmed", tech);
const done = await job("completed", tech);
const open = await job("pending", null);

await as(tech);
check("assigned technician, in progress: gets the phone", (await phoneFor(active)) === "09171234567");
check("assigned technician, confirmed: gets the phone", (await phoneFor(confirmed)) === "09171234567");
check("assigned technician, completed: nothing", (await phoneFor(done)) === null);
check("a pending job with nobody assigned: nothing", (await phoneFor(open)) === null);
await as(other);
check("a different technician: nothing", (await phoneFor(active)) === null);
await as(null);
check("signed out: nothing", (await phoneFor(active)) === null);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
