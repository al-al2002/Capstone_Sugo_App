// Checks that a technician must pass EVERY skill assessment before submitting
// their registration (20261122000003), in PGlite:
//   * one of two tracks passed -> refused, saying how many are left;
//   * both passed -> submitted;
//   * a track counts as passed when any of its brands is verified;
//   * removing the unpassed skill lets them submit with the rest;
//   * accounts already submitted are untouched.
//
//   node all_assessments.mjs ../../../supabase/migrations
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

// Only what the function reads, as earlier migrations left it.
await db.exec(`
  create role authenticated;
  create role anon;
  create role service_role;
  create schema auth;
  create table auth.users (id uuid primary key, email_confirmed_at timestamptz);
  create table public.profiles (
    id uuid primary key, role text, registration_status text default 'incomplete',
    registration_step text
  );
  create table public.technicians (
    id uuid primary key, base_latitude double precision, base_longitude double precision
  );
  create table public.identity_verifications (user_id uuid, status text);
  create table public.technician_specializations (
    technician_id uuid, device_type text, brand text, track text, verified boolean default false
  );
  create table public.technician_verification_documents (
    technician_id uuid, doc_type text, status text
  );
  create table public.client_saved_addresses (client_id uuid);
  create function public.activate_account(p uuid) returns text language sql as $$ select 'active' $$;
`);
await db.exec(readFileSync(`${MIG}/20261122000003_require_all_assessments.sql`, "utf8"));
console.log("migration applied\n");

async function technician(tracks) {
  const id = uuid();
  await q("insert into profiles(id, role) values ($1, 'technician')", [id]);
  await q("insert into technicians(id, base_latitude, base_longitude) values ($1, 7.07, 125.61)", [id]);
  await q("insert into identity_verifications(user_id, status) values ($1, 'pending')", [id]);
  await q("insert into technician_verification_documents values ($1, 'nbi_clearance', 'pending')", [id]);
  for (const [device, track, verified] of tracks) {
    await q(
      "insert into technician_specializations(technician_id, device_type, brand, track, verified) values ($1,$2,'Any',$3,$4)",
      [id, device, track, verified],
    );
  }
  return id;
}
const submit = async (id) => (await q("select public.submit_registration_for_review($1) as r", [id])).rows[0].r;
async function refused(name, id, needle) {
  try {
    await submit(id);
    check(name, false, "was not refused");
  } catch (e) {
    check(name, String(e.message).includes(needle), e.message);
  }
}

const half = await technician([
  ["laptop", "computer_repair", true],
  ["aircon", "appliance_service", false],
]);
await refused("one of two assessments passed: refused", half, "Pass every skill assessment");
await refused("...and it says how many are left", half, "(1 still to pass)");

const both = await technician([
  ["laptop", "computer_repair", true],
  ["aircon", "appliance_service", true],
]);
check("both passed: submitted", (await submit(both)).registration_status === "pending_review");

// Two brands in one track, one of them verified: the track is passed.
const brands = await technician([
  ["laptop", "computer_repair", true],
  ["desktop", "computer_repair", false],
]);
check("a track counts as passed when any brand in it is verified",
  (await submit(brands)).registration_status === "pending_review");

// Removing the unpassed skill is a way forward.
await q("delete from technician_specializations where technician_id = $1 and track = 'appliance_service'", [half]);
check("after removing the failed skill: submitted",
  (await submit(half)).registration_status === "pending_review");

const none = await technician([["aircon", "appliance_service", false]]);
await refused("nothing passed: refused", none, "(1 still to pass)");

// Already submitted: a no-op, never re-checked against the new rule.
const old = await technician([["aircon", "appliance_service", false]]);
await q("update profiles set registration_status = 'pending_review' where id = $1", [old]);
const r = await submit(old);
check("an account already submitted is untouched",
  r.registration_status === "pending_review" && r.changed === false, JSON.stringify(r));

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
