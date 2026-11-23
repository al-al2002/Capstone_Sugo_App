// Checks in-task documentation (20261122000002) in PGlite:
//   * only the assigned technician adds checkpoints, only while the job is
//     under way, 1-4 photos from this job's folder, "intake" before "after";
//   * job_evidence_missing lists intake/after until both exist, is empty for
//     a community question, and for a job posted before the migration;
//   * the client and technician read the record, nobody else does, and no
//     one can change or delete it;
//   * the storage helpers allow the same people the table does.
//
//   node job_evidence.mjs ../../../supabase/migrations
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { randomUUID as uuid } from "node:crypto";

const MIG = process.argv[2];
const db = new PGlite();
const q = (sql, params = []) => db.query(sql, params);
const one = async (sql, params = []) => (await q(sql, params)).rows[0];
let failures = 0;
const check = (name, ok, detail = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(68)} ${ok ? "" : detail}`);
};
async function raises(name, fn, needle) {
  try {
    await fn();
    check(name, false, "did not raise");
  } catch (e) {
    check(name, !needle || String(e.message).includes(needle), e.message);
  }
}
const as = (id) => db.exec(`select set_config('request.jwt.claim.sub', '${id ?? ""}', false)`);

// Only what the migration touches, as earlier migrations left it.
await db.exec(`
  create role authenticated;
  create role anon;
  create role service_role;
  create schema auth;
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
  grant usage on schema auth to authenticated, anon;

  create table public.profiles (id uuid primary key, role text);
  create table public.technicians (id uuid primary key references public.profiles(id));
  create table public.jobs (
    id uuid primary key default gen_random_uuid(),
    client_id uuid not null references public.profiles(id),
    assigned_technician_id uuid references public.technicians(id),
    status text not null default 'pending',
    service_path text,
    created_at timestamptz default now()
  );
  grant usage on schema public to authenticated;
  grant select on public.jobs to authenticated;

  create schema storage;
  create table storage.buckets (
    id text primary key, name text, public boolean,
    file_size_limit bigint, allowed_mime_types text[]
  );
  create table storage.objects (bucket_id text, name text);
  alter table storage.objects enable row level security;
  create function storage.foldername(name text) returns text[] language sql immutable as $$
    select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
  $$;
`);

const client = uuid();
const technician = uuid();
const stranger = uuid();
await q("insert into profiles(id, role) values ($1,'client'), ($2,'technician'), ($3,'technician')", [client, technician, stranger]);
await q("insert into technicians(id) values ($1), ($2)", [technician, stranger]);

const newJob = (path = "home_service", status = "in_progress") =>
  one(
    "insert into jobs(client_id, assigned_technician_id, status, service_path) values ($1,$2,$3,$4) returning id",
    [client, technician, status, path],
  ).then((r) => r.id);

// Posted before the requirement existed - must stay completable.
const oldJob = await newJob();
await db.exec("select pg_sleep(0.01)");

await db.exec(readFileSync(`${MIG}/20261122000002_job_evidence.sql`, "utf8"));
console.log("migration applied\n");

const bucket = await one("select public, file_size_limit from storage.buckets where id = 'job-evidence'");
check("the photo bucket exists and is private", bucket && bucket.public === false, JSON.stringify(bucket));

const job = await newJob();
const community = await newJob("it_community");
const done = await newJob("home_service", "completed");

const missing = async (id) => (await one("select public.job_evidence_missing($1) as m", [id])).m;
const add = (id, milestone, paths, extra = {}) =>
  one(
    "select * from public.add_job_evidence($1,$2,$3,$4,$5,$6,$7)",
    [id, milestone, paths, extra.note ?? null, extra.lat ?? null, extra.lng ?? null, extra.acc ?? null],
  );

// ------------------------------------------------------------- missing
await as(technician);
check("new home visit: Before and After are required",
  JSON.stringify(await missing(job)) === JSON.stringify(["intake", "after"]), JSON.stringify(await missing(job)));
check("community question: nothing required", (await missing(community)).length === 0);
check("job posted before the migration: exempt", (await missing(oldJob)).length === 0);
await as(null);
check("service role (no user) can ask too", (await missing(job)).length === 2);
await as(stranger);
await raises("a stranger cannot read what is missing", () => missing(job), "Only the client and the technician");

// ------------------------------------------------------------- adding
await as(technician);
await raises("'after' before 'intake' is refused",
  () => add(job, "after", [`${job}/a.jpg`]), "as you found it first");
await raises("a photo from another booking is refused",
  () => add(job, "intake", [`${community}/a.jpg`]), "does not belong");
await raises("no photos is refused", () => add(job, "intake", []), "between 1 and 4");
await raises("five photos is refused",
  () => add(job, "intake", [1, 2, 3, 4, 5].map((n) => `${job}/${n}.jpg`)), "between 1 and 4");
await raises("an unknown step is refused", () => add(job, "selfie", [`${job}/a.jpg`]), "not a step");
await raises("a 501-character note is refused",
  () => add(job, "intake", [`${job}/a.jpg`], { note: "x".repeat(501) }), "500");

const intake = await add(job, "intake", [`${job}/before-1.jpg`, `${job}/before-2.jpg`],
  { note: "  Screen cracked on arrival  ", lat: 7.0731, lng: 125.6128, acc: 8 });
check("the technician adds the Before photos", intake?.milestone === "intake");
check("the note is trimmed", intake?.note === "Screen cracked on arrival", intake?.note);
check("the location stamp is kept", intake?.latitude === 7.0731 && intake?.longitude === 125.6128);
check("the time is set by the database", intake?.captured_at instanceof Date);
check("now only After is missing", JSON.stringify(await missing(job)) === JSON.stringify(["after"]));

const half = await add(job, "progress", [`${job}/p.jpg`], { lat: 7.07 });
check("a latitude with no longitude is not stored half", half.latitude === null && half.longitude === null);

await add(job, "after", [`${job}/after.jpg`]);
check("with Before and After in, nothing is missing", (await missing(job)).length === 0);

await raises("a finished job takes no more photos",
  () => add(done, "intake", [`${done}/a.jpg`]), "under way");
await as(client);
await raises("the client cannot add to the work record",
  () => add(job, "diagnosis", [`${job}/c.jpg`]), "Only the technician");
await as(stranger);
await raises("another technician cannot add to it",
  () => add(job, "diagnosis", [`${job}/s.jpg`]), "Only the technician");
await as(null);
await raises("signed out cannot add", () => add(job, "diagnosis", [`${job}/n.jpg`]), "Sign in");

// ------------------------------------------------------------- reading
async function asRole(id, sql, params = []) {
  await as(id);
  await db.exec("set role authenticated");
  try {
    return await q(sql, params);
  } finally {
    await db.exec("reset role");
  }
}
const seenBy = async (id) =>
  (await asRole(id, "select count(*)::int as n from public.job_evidence where job_id = $1", [job])).rows[0].n;
// Three checkpoints were added above: intake, progress, after.
check("the client reads the work record", (await seenBy(client)) === 3, String(await seenBy(client)));
check("the technician reads it", (await seenBy(technician)) === 3);
check("a stranger sees nothing", (await seenBy(stranger)) === 0);

await raises("the technician cannot edit a record",
  () => asRole(technician, "update public.job_evidence set note = 'changed' where job_id = $1", [job]), "permission denied");
await raises("the technician cannot delete a record",
  () => asRole(technician, "delete from public.job_evidence where job_id = $1", [job]), "permission denied");

// ------------------------------------------------------------- storage
const canUpload = async (id, path) => {
  await as(id);
  return (await one("select public.can_upload_job_evidence($1) as ok", [path])).ok;
};
const canRead = async (id, path) => {
  await as(id);
  return (await one("select public.can_read_job_evidence($1) as ok", [path])).ok;
};
check("storage: the technician uploads into the job's folder", await canUpload(technician, `${job}/x.jpg`));
check("storage: the client cannot upload", !(await canUpload(client, `${job}/x.jpg`)));
check("storage: no uploads once the job is finished", !(await canUpload(technician, `${done}/x.jpg`)));
check("storage: a malformed path is a no, not an error", !(await canUpload(technician, "not-a-uuid/x.jpg")));
check("storage: the client reads the photos", await canRead(client, `${job}/x.jpg`));
check("storage: a stranger cannot read them", !(await canRead(stranger, `${job}/x.jpg`)));

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
