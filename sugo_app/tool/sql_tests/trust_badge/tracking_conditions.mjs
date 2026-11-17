// Checks the trip-conditions columns (20261117000005) in PGlite:
//   * only the server (not `authenticated`) can write them, on insert or update;
//   * a new leg (stage change) clears them;
//   * out-of-range readings are refused.
//
//   node tracking_conditions.mjs ../../../supabase/migrations
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { randomUUID as uuid } from "node:crypto";

const MIG = process.argv[2];
const db = new PGlite();
const q = (sql, params = []) => db.query(sql, params);
let failures = 0;
const check = (name, ok, detail = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(60)} ${ok ? "" : detail}`);
};

// A minimal job_tracking with every column the guard touches, as the earlier
// migrations (20260916000003, 20260929000001) left it.
await db.exec(`
  create role authenticated;
  create role anon;
  create table public.job_tracking (
    id uuid primary key default gen_random_uuid(),
    job_id uuid not null unique,
    stage text not null,
    expected_arrival_at timestamptz, projected_arrival_at timestamptz,
    delay_minutes numeric(6,1), delay_reason text,
    eta_sampled_at timestamptz, delay_notified_at timestamptz,
    client_latitude double precision, client_longitude double precision,
    client_accuracy_m double precision, client_position_at timestamptz,
    client_trip_started_at timestamptz, client_arrived_at timestamptz
  );
`);
await db.exec(readFileSync(`${MIG}/20261117000005_tracking_conditions.sql`, "utf8"));
// The update trigger itself is from 20260916000003; the migration above only
// replaces the function it calls.
await db.exec(`
  create trigger job_tracking_guard_eta before update on public.job_tracking
    for each row execute function public.guard_tracking_eta_columns();
  grant select, insert, update on public.job_tracking to authenticated;
`);

const row = async (job) =>
  (await q("select * from job_tracking where job_id = $1", [job])).rows[0];
const asApp = () => db.exec("set role authenticated");
const asServer = () => db.exec("reset role");

// ------------------------------------------------------------- insert
const job = uuid();
await asApp();
await q(
  `insert into job_tracking (job_id, stage, traffic_label, traffic_congestion,
     weather_label, weather_severity)
   values ($1, 'heading_to_pickup', 'clear roads', 0.01, 'clear weather', 0)`,
  [job],
);
await asServer();
let r = await row(job);
check("app insert: conditions start empty",
  r.traffic_label === null && r.traffic_congestion === null &&
    r.weather_label === null && r.weather_severity === null,
  JSON.stringify(r));

// ------------------------------------------------------- server writes
await q(
  `update job_tracking set traffic_label = 'heavy traffic',
     traffic_congestion = 0.72, weather_label = 'light rain',
     weather_severity = 0.55 where job_id = $1`,
  [job],
);
r = await row(job);
check("server update: conditions saved",
  r.traffic_label === "heavy traffic" && Number(r.traffic_congestion) === 0.72 &&
    r.weather_label === "light rain" && Number(r.weather_severity) === 0.55,
  JSON.stringify(r));

// ---------------------------------------------- the app cannot rewrite
await asApp();
await q(
  `update job_tracking set traffic_label = 'clear roads',
     traffic_congestion = 0, weather_label = 'clear weather',
     weather_severity = 0 where job_id = $1`,
  [job],
);
await asServer();
r = await row(job);
check("app update: a technician cannot whitewash the traffic",
  r.traffic_label === "heavy traffic" && Number(r.traffic_congestion) === 0.72,
  JSON.stringify(r));
check("app update: ...or the weather",
  r.weather_label === "light rain" && Number(r.weather_severity) === 0.55,
  JSON.stringify(r));

// ------------------------------------------------------------ new leg
await asApp();
await q("update job_tracking set stage = 'collected' where job_id = $1", [job]);
await asServer();
r = await row(job);
check("a new leg clears the old leg's conditions",
  r.stage === "collected" && r.traffic_label === null && r.weather_label === null &&
    r.traffic_congestion === null && r.weather_severity === null,
  JSON.stringify(r));

// ------------------------------------------------------------- ranges
let refused = false;
try {
  await q("update job_tracking set traffic_congestion = 1.5 where job_id = $1", [job]);
} catch (e) {
  refused = e.code === "23514";
}
check("congestion above 1 is refused", refused);

refused = false;
try {
  await q("update job_tracking set weather_severity = -0.1 where job_id = $1", [job]);
} catch (e) {
  refused = e.code === "23514";
}
check("severity below 0 is refused", refused);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
