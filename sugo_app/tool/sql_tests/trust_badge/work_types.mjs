// Checks technician work types (20261117000007) in PGlite:
//   * the two columns exist, default to both, and cannot both be false;
//   * technicians registered before the migration are set to both;
//   * the candidate view carries them, for the engine's Stage 1 gate;
//   * match_technicians_for_job lists only technicians who take the job's
//     kind of work: Home Service -> offers_home_service, Shop Repair ->
//     offers_shop_repair.
//
//   node work_types.mjs ../../../supabase/migrations
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

// The objects the view and the function read, as earlier migrations left
// them - only the columns they touch - plus stubs for their helpers.
await db.exec(`
  create role authenticated;
  create role anon;
  create role service_role;
  create schema auth;
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
  grant usage on schema auth to authenticated, anon;

  create table public.profiles (
    id uuid primary key, full_name text, avatar_url text, phone text,
    registration_status text not null default 'active'
  );
  create table public.technicians (
    id uuid primary key references public.profiles(id),
    skill_tags text[] not null default '{}', tier text default 'standard',
    specialization text[] not null default '{}', is_verified boolean default true,
    is_available boolean default false, badge text, rating numeric,
    total_jobs integer default 0, current_workload integer default 0,
    latitude double precision, longitude double precision,
    base_latitude numeric(9,6), base_longitude numeric(9,6),
    service_radius_km numeric(5,2) default 10, verification_tier text default 'basic',
    created_at timestamptz default now(), barangay text
  );
  create table public.identity_verifications (user_id uuid, status text);
  create table public.technician_specializations (
    technician_id uuid, device_type text, brand text, skill_level text,
    verified boolean default true, track text, created_at timestamptz default now()
  );
  create table public.jobs (
    id uuid primary key, client_id uuid, device_type text, device_detail text,
    brand text, latitude double precision, longitude double precision,
    service_path text
  );
  create view public.technician_review_stats as
    select null::uuid as technician_id, null::numeric as average_stars,
           null::integer as review_count where false;
  create function public.technician_away_until(uuid) returns date
    language sql stable as $$ select null::date $$;
  create function public.haversine_km(double precision, double precision,
    double precision, double precision) returns double precision
    language sql immutable as $$ select abs($1 - $3) * 111 + abs($2 - $4) * 111 $$;
  create function public.job_device_candidates(text, text) returns text[]
    language sql immutable as $$ select array[$1] $$;
  create type public.technician_card as (
    id uuid, full_name text, avatar_url text, tier text, badge text,
    is_verified boolean, is_available boolean, rating numeric,
    review_count integer, total_jobs integer, is_new boolean,
    distance_km numeric, specializations jsonb, primary_device_type text,
    primary_brand text, match_rank integer, is_top_match boolean
  );
`);

// Three technicians registered BEFORE the migration: they must come out as
// doing both.
const client = uuid();
const homeOnly = uuid();
const shopOnly = uuid();
const both = uuid();
const legacy = [homeOnly, shopOnly, both];
for (const [i, id] of legacy.entries()) {
  await q("insert into profiles (id, full_name) values ($1, $2)", [id, `Tech ${i}`]);
  await q(
    `insert into technicians (id, base_latitude, base_longitude)
     values ($1, 7.07, 125.61)`,
    [id],
  );
  await q("insert into identity_verifications values ($1, 'approved')", [id]);
  await q(
    "insert into technician_specializations (technician_id, device_type) values ($1, 'laptop')",
    [id],
  );
}

await db.exec(readFileSync(`${MIG}/20261117000007_technician_work_types.sql`, "utf8"));

// ------------------------------------------------------------ the backfill
let r = await q(
  "select count(*)::int as n from technicians where offers_home_service and offers_shop_repair",
);
check("every technician registered before it does both", r.rows[0].n === 3,
  JSON.stringify(r.rows));

// ------------------------------------------------------------ the columns
let err = null;
try {
  await q(
    "update technicians set offers_home_service = false, offers_shop_repair = false where id = $1",
    [both],
  );
} catch (e) {
  err = e.code;
}
check("a technician cannot take neither", err === "23514", String(err));

await q("update technicians set offers_shop_repair = false where id = $1", [homeOnly]);
await q("update technicians set offers_home_service = false where id = $1", [shopOnly]);

const fresh = uuid();
await q("insert into profiles (id) values ($1)", [fresh]);
await q("insert into technicians (id) values ($1)", [fresh]);
r = await q("select offers_home_service, offers_shop_repair from technicians where id = $1", [fresh]);
check("a new row defaults to both",
  r.rows[0].offers_home_service === true && r.rows[0].offers_shop_repair === true);

// --------------------------------------------------------------- the view
r = await q(
  "select id, offers_home_service, offers_shop_repair from matching_candidates where id = $1",
  [shopOnly],
);
check("the candidate view carries both columns",
  r.rows[0]?.offers_home_service === false && r.rows[0]?.offers_shop_repair === true,
  JSON.stringify(r.rows));

// ------------------------------------------------------------ the listing
const listFor = async (path) => {
  const job = uuid();
  await db.exec("reset role");
  await q(
    `insert into jobs (id, client_id, device_type, latitude, longitude, service_path)
     values ($1, $2, 'laptop', 7.07, 125.61, $3)`,
    [job, client, path],
  );
  await db.exec(`set request.jwt.claim.sub = '${client}'`);
  await db.exec("set role authenticated");
  const res = await q("select id from public.match_technicians_for_job($1, 20)", [job]);
  await db.exec("reset role");
  return new Set(res.rows.map((x) => x.id));
};

let ids = await listFor("home_service");
check("Home Service lists the home-service technicians",
  ids.has(homeOnly) && ids.has(both), [...ids].join(","));
check("...and never the shop-only one", !ids.has(shopOnly));

ids = await listFor("pickup");
check("Shop Repair lists the shop technicians",
  ids.has(shopOnly) && ids.has(both), [...ids].join(","));
check("...and never the home-only one", !ids.has(homeOnly));

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
