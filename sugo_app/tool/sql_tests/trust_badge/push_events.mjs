// Checks the two pushes added in 20261117000008, in PGlite:
//   * "Cancel request" (withdraw_technician_offer) tells the technician who
//     was waiting, and still returns what it did;
//   * "I've arrived" (end_collection_trip) tells the technician, once, with
//     the stage - and a new trip can announce again.
//
//   node push_events.mjs ../../../supabase/migrations
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { randomUUID as uuid } from "node:crypto";

const MIG = process.argv[2];
const db = new PGlite();
const q = (sql, params = []) => db.query(sql, params);
let failures = 0;
const check = (name, ok, detail = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(64)} ${ok ? "" : detail}`);
};

await db.exec(`
  create role authenticated;
  create role anon;
  create schema auth;
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
  grant usage on schema auth to authenticated, anon;

  create table public.jobs (
    id uuid primary key, client_id uuid not null, status text not null,
    service_path text, delivery_option text, assigned_technician_id uuid
  );
  create table public.job_matches (
    id uuid primary key default gen_random_uuid(), job_id uuid, technician_id uuid,
    status text
  );
  create table public.booking_cancellations (
    client_id uuid, job_id uuid, technician_id uuid, kind text
  );
  create function public.booking_cooldown_until(uuid) returns timestamptz
    language sql stable as $$ select null::timestamptz $$;
  create table public.job_tracking (
    id uuid primary key default gen_random_uuid(),
    job_id uuid not null unique references public.jobs(id),
    technician_id uuid not null,
    stage text not null default 'heading_to_pickup',
    latitude double precision, longitude double precision,
    expected_arrival_at timestamptz, projected_arrival_at timestamptz,
    delay_minutes numeric(6,1), delay_reason text,
    eta_sampled_at timestamptz, delay_notified_at timestamptz,
    client_latitude double precision, client_longitude double precision,
    client_accuracy_m double precision, client_position_at timestamptz,
    client_trip_started_at timestamptz, client_arrived_at timestamptz,
    constraint job_tracking_stage_check check (stage in (
      'heading_to_pickup','collected','returning_to_shop','in_repair',
      'out_for_delivery','ready_for_collection','delivered'))
  );
  create table public.pushed (event jsonb);
  create function public.push_event(p_event jsonb) returns void
    language sql security definer as $$ insert into public.pushed values (p_event) $$;
`);
await db.exec(readFileSync(`${MIG}/20261117000005_tracking_conditions.sql`, "utf8"));
await db.exec(`
  create trigger job_tracking_guard_eta before update on public.job_tracking
    for each row execute function public.guard_tracking_eta_columns();
  grant select, insert, update on public.job_tracking to authenticated;
`);
await db.exec(readFileSync(`${MIG}/20261117000006_drop_off_trip.sql`, "utf8"));
await db.exec(readFileSync(`${MIG}/20261117000008_more_push_events.sql`, "utf8"));

const client = uuid();
const technician = uuid();

const as = async (who) => {
  await db.exec("reset role");
  await db.exec(`set request.jwt.claim.sub = '${who}'`);
  await db.exec("set role authenticated");
};
const pushes = async (job, type) => {
  await db.exec("reset role");
  return (await q(
    "select event from pushed where event->>'job_id' = $1 and event->>'type' = $2",
    [job, type],
  )).rows.map((r) => r.event);
};

// ------------------------------------------------------- cancel request
const job = uuid();
await q(
  `insert into jobs (id, client_id, status, service_path) values ($1, $2, 'matched', 'home_service')`,
  [job, client],
);
await q(
  "insert into job_matches (job_id, technician_id, status) values ($1, $2, 'offered')",
  [job, technician],
);
await as(client);
const res = await q("select public.withdraw_technician_offer($1) as r", [job]);
check("cancel request still returns what it did",
  res.rows[0].r.status === "withdrawn" && res.rows[0].r.technician_id === technician,
  JSON.stringify(res.rows[0]));
let p = await pushes(job, "withdrawn");
check("the waiting technician is told",
  p.length === 1 && p[0].technician_id === technician, JSON.stringify(p));

// ------------------------------------------------------------- arriving
const dropOff = uuid();
await db.exec("reset role");
await q(
  `insert into jobs (id, client_id, status, service_path, delivery_option, assigned_technician_id)
   values ($1, $2, 'confirmed', 'pickup', 'self', $3)`,
  [dropOff, client, technician],
);
await as(client);
await q("select public.start_collection_trip($1)", [dropOff]);
await q("select public.end_collection_trip($1)", [dropOff]);
p = await pushes(dropOff, "arrived");
check("\"I've arrived\" tells the technician, with the stage",
  p.length === 1 && p[0].stage === "dropping_off", JSON.stringify(p));

await as(client);
await q("select public.end_collection_trip($1)", [dropOff]);
p = await pushes(dropOff, "arrived");
check("tapping it again does not tell them twice", p.length === 1, JSON.stringify(p));

// A new trip (set off again) is a new arrival.
await as(client);
await q("select public.start_collection_trip($1)", [dropOff]);
await q("select public.end_collection_trip($1)", [dropOff]);
p = await pushes(dropOff, "arrived");
check("a new trip announces its own arrival", p.length === 2, JSON.stringify(p));

let err = null;
try {
  await as(uuid());
  await q("select public.end_collection_trip($1)", [dropOff]);
} catch (e) {
  err = e.code;
}
check("nobody else can end the trip", err === "42501", String(err));

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
