// Checks the drop-off trip (20261117000006) in PGlite:
//   * "I'm on my way" on a confirmed self drop-off creates the tracking row at
//     `dropping_off`, owned by the assigned technician, and tells them once;
//   * only that job's client can start, share and end it;
//   * a delivery job, or one not yet confirmed, cannot start a trip;
//   * "Unit received" (the technician moving it to in_repair) wipes the
//     client's position and closes sharing;
//   * the collection trip (ready_for_collection) still works as before.
//
//   node drop_off_trip.mjs ../../../supabase/migrations
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { randomUUID as uuid } from "node:crypto";

const MIG = process.argv[2];
const db = new PGlite();
const q = (sql, params = []) => db.query(sql, params);
let failures = 0;
const check = (name, ok, detail = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(66)} ${ok ? "" : detail}`);
};

// The tables as earlier migrations left them - only the columns these
// functions and the guard touch - plus stubs for auth.uid() and push_event().
await db.exec(`
  create role authenticated;
  create role anon;
  create schema auth;
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
  grant usage on schema auth to authenticated, anon;

  create table public.jobs (
    id uuid primary key,
    client_id uuid not null,
    status text not null,
    service_path text,
    delivery_option text,
    assigned_technician_id uuid
  );
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

const client = uuid();
const technician = uuid();
const stranger = uuid();

const as = async (who) => {
  await db.exec("reset role");
  await db.exec(`set request.jwt.claim.sub = '${who}'`);
  await db.exec("set role authenticated");
};
const asServer = async () => {
  await db.exec("reset role");
  await db.exec("set request.jwt.claim.sub = ''");
};
const row = async (job) => {
  await asServer();
  return (await q("select * from job_tracking where job_id = $1", [job])).rows[0];
};
const pushes = async (job) => {
  await asServer();
  return (await q("select event from pushed where event->>'job_id' = $1", [job]))
    .rows.map((r) => r.event);
};
const code = async (fn) => {
  try {
    await fn();
    return null;
  } catch (e) {
    return e.code;
  }
};
const newJob = async ({ status = "confirmed", path = "pickup", option = "self" } = {}) => {
  await asServer();
  const id = uuid();
  await q(
    `insert into jobs (id, client_id, status, service_path, delivery_option,
       assigned_technician_id) values ($1, $2, $3, $4, $5, $6)`,
    [id, client, status, path, option, technician],
  );
  return id;
};

// ------------------------------------------------------------ the stage
await asServer();
const probe = await newJob();
let err = await code(() =>
  q("insert into job_tracking (job_id, technician_id, stage) values ($1, $2, 'dropping_off')",
    [probe, technician]));
check("the stage check accepts dropping_off", err === null, String(err));
err = await code(() =>
  q("update job_tracking set stage = 'teleporting' where job_id = $1", [probe]));
check("...and still refuses anything else", err === "23514", String(err));

// --------------------------------------------------- "I'm on my way"
const job = await newJob();
await as(client);
err = await code(() => q("select public.start_collection_trip($1)", [job]));
check("the client starts the drop-off trip", err === null, String(err));
let r = await row(job);
check("it creates the row at dropping_off",
  r?.stage === "dropping_off", JSON.stringify(r));
check("...owned by the assigned technician",
  r?.technician_id === technician, JSON.stringify(r));
check("...with the trip open", r?.client_trip_started_at !== null && r?.client_arrived_at === null);
let p = await pushes(job);
check("the technician is told once, as a drop-off",
  p.length === 1 && p[0].type === "collection" && p[0].stage === "dropping_off",
  JSON.stringify(p));

await as(client);
await q("select public.start_collection_trip($1)", [job]);
p = await pushes(job);
check("tapping again does not tell them twice", p.length === 1, JSON.stringify(p));

// ----------------------------------------------------- who may share
await as(client);
err = await code(() =>
  q("select public.share_collection_position($1, 7.07, 125.61, 9)", [job]));
r = await row(job);
check("the client shares a position",
  err === null && r.client_latitude === 7.07 && r.client_longitude === 125.61,
  String(err));

await as(stranger);
err = await code(() =>
  q("select public.share_collection_position($1, 1, 1, 9)", [job]));
check("a stranger cannot share on it", err === "42501", String(err));
err = await code(() => q("select public.start_collection_trip($1)", [job]));
check("...or start it", err === "42501", String(err));

// ------------------------------------------------- who may not start
const delivery = await newJob({ option: "delivery" });
await as(client);
err = await code(() => q("select public.start_collection_trip($1)", [delivery]));
check("a delivery job has no drop-off trip", err === "P0002", String(err));
check("...and gets no row", (await row(delivery)) === undefined);

const waiting = await newJob({ status: "matched" });
await as(client);
err = await code(() => q("select public.start_collection_trip($1)", [waiting]));
check("not before the technician accepts", err === "23514", String(err));

// ------------------------------------------------------ "Unit received"
await as(technician);
await q("update job_tracking set stage = 'in_repair' where job_id = $1", [job]);
r = await row(job);
check("unit received: the stage moves to in_repair", r.stage === "in_repair");
check("...and the client's position is wiped",
  r.client_latitude === null && r.client_longitude === null &&
    r.client_trip_started_at === null, JSON.stringify(r));
await as(client);
err = await code(() =>
  q("select public.share_collection_position($1, 7.08, 125.62, 9)", [job]));
check("...and sharing is closed", err === "42501", String(err));

// ------------------------------------------------------------ arriving
const arriving = await newJob();
await as(client);
await q("select public.start_collection_trip($1)", [arriving]);
await q("select public.share_collection_position($1, 7.07, 125.61, 9)", [arriving]);
err = await code(() => q("select public.end_collection_trip($1)", [arriving]));
r = await row(arriving);
check("\"I've arrived\" ends a drop-off trip",
  err === null && r.client_arrived_at !== null && r.client_latitude === null,
  String(err));

// ------------------------------------------- the collection trip, as before
const collect = await newJob({ option: "delivery" });
await asServer();
await q(
  "insert into job_tracking (job_id, technician_id, stage) values ($1, $2, 'ready_for_collection')",
  [collect, technician],
);
await as(client);
err = await code(() => q("select public.start_collection_trip($1)", [collect]));
p = await pushes(collect);
check("the collection trip still starts",
  err === null && p.length === 1 && p[0].stage === "ready_for_collection",
  `${err} ${JSON.stringify(p)}`);
await as(client);
err = await code(() =>
  q("select public.share_collection_position($1, 7.07, 125.61, 9)", [collect]));
check("...and still shares", err === null, String(err));

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
