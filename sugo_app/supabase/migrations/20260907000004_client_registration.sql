-- SUGO: client trust profile, saved addresses, phone verification
--
-- The client side of registration. Three tables, one of which
-- (`phone_verifications`) is not in the brief but is required to implement the
-- OTP step honestly - see section 3.
--
-- Every `client_id` below references `profiles`, not a `clients` table. There
-- is no clients table in SUGO and there is not meant to be: a client IS a row
-- in `profiles`, which is what lets these policies compare straight against
-- `auth.uid()` with no join.

-- ---------------------------------------------------------------------------
-- 1. The trust profile
-- ---------------------------------------------------------------------------
--
-- Exists so a technician can decide whether to accept a job. The asymmetry is
-- deliberate: a client sees a technician's rating, tier and verification
-- badges, and until now a technician saw nothing at all about the person whose
-- house they were about to travel to.

create table if not exists public.client_verification_status (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique references public.profiles(id) on delete cascade,

  phone_verified boolean not null default false,
  phone_verified_at timestamptz,

  -- Incremented by the booking flow when a technician reports arriving to
  -- nobody. Not a column the client can touch - see the guard in section 5.
  no_show_count integer not null default 0 check (no_show_count >= 0),

  -- Null until enough technicians have rated them. Null and 0 must stay
  -- distinguishable: "nobody has rated this client yet" is neutral, whereas a
  -- literal 0 would read as unanimously terrible and freeze out every new user.
  avg_rating_from_technicians numeric(3,2)
    check (avg_rating_from_technicians is null
           or (avg_rating_from_technicians >= 0
               and avg_rating_from_technicians <= 5)),

  trust_level text not null default 'new'
    check (trust_level in ('new', 'verified', 'trusted')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.client_verification_status is
  'What a technician is shown about a client before accepting a job. '
  'trust_level: new -> verified (ID approved) -> trusted (earned over time).';

create index if not exists idx_client_verification_client
  on public.client_verification_status (client_id);

drop trigger if exists client_verification_touch on public.client_verification_status;
create trigger client_verification_touch
  before update on public.client_verification_status
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Saved addresses
-- ---------------------------------------------------------------------------
--
-- The registration flow captures one, but the table is built for many from the
-- start ("Home", "Office", "Mum's place") because retrofitting a one-to-many
-- later would mean migrating live address data.

create table if not exists public.client_saved_addresses (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(id) on delete cascade,

  label text not null default 'Home',
  latitude numeric(9,6) not null,
  longitude numeric(9,6) not null,

  -- What Nominatim returned, or what the user typed over it. Stored as text
  -- rather than parsed into street/barangay/city columns: Philippine addresses
  -- do not reliably decompose that way, and the technician needs the string a
  -- human wrote, not a normalised one.
  address_text text not null,

  -- Free-text extras the map cannot know: "green gate", "ask for Ate Beth".
  notes text,

  is_default boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.client_saved_addresses is
  'Client addresses. Exactly one row per client may be is_default = true, '
  'enforced by a partial unique index.';

create index if not exists idx_client_addresses_client
  on public.client_saved_addresses (client_id);

-- Exactly one default per client. A partial unique index is the right tool:
-- it constrains only the rows where `is_default` is true, leaving any number
-- of non-default addresses.
create unique index if not exists uniq_client_default_address
  on public.client_saved_addresses (client_id)
  where is_default = true;

-- Making an address the default has to clear the previous one, and the unique
-- index above means doing it in the wrong order fails. Rather than make every
-- caller remember to unset first, this trigger demotes the others as part of
-- the same statement.
create or replace function public.enforce_single_default_address()
returns trigger
language plpgsql
as $function$
begin
  if new.is_default then
    update public.client_saved_addresses
    set is_default = false
    where client_id = new.client_id
      and id <> new.id
      and is_default;
  end if;
  return new;
end;
$function$;

drop trigger if exists client_addresses_single_default on public.client_saved_addresses;
create trigger client_addresses_single_default
  before insert or update on public.client_saved_addresses
  for each row execute function public.enforce_single_default_address();

-- ---------------------------------------------------------------------------
-- 3. Phone verification codes
-- ---------------------------------------------------------------------------
--
-- WHY THIS TABLE IS NOT IN THE BRIEF. The brief specifies a `phone_verified`
-- boolean and a stubbed SMS provider, which is enough to draw the screen but
-- not enough to implement it: something has to remember which code was sent to
-- which number, and when it expires. Keeping that in Flutter state would mean
-- the app knows the correct code, and "verification" the client can read is
-- not verification at all.
--
-- So the code lives here, unreadable by the client (section 5), and is checked
-- server-side by `verify_phone_code()`.
--
-- The code is stored in plain text. That is a deliberate, stated limitation:
-- it is a six-digit number valid for ten minutes, and anyone who can read this
-- table already has the service role and could set `phone_verified` directly.
-- Hashing it would protect against nothing that is not already lost.

create table if not exists public.phone_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  phone text not null,
  code text not null,

  -- Rate limiting and brute-force resistance. A six-digit code is one in a
  -- million per guess, but unlimited guesses reduce that to a certainty; five
  -- attempts keeps a genuine typo recoverable while making a search hopeless.
  attempts integer not null default 0,
  max_attempts integer not null default 5,

  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.phone_verifications is
  'Outstanding OTP codes. Rows are never read by the client: the code column '
  'is revoked from anon and authenticated, and checking happens server-side.';

create index if not exists idx_phone_verifications_user
  on public.phone_verifications (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 4. Sending and checking a code
-- ---------------------------------------------------------------------------
--
-- How long a code is good for. Ten minutes: long enough to survive a delayed
-- SMS and a user who switches apps to read it, short enough that a code
-- glimpsed on a lock screen is not useful an hour later.
create or replace function public.phone_code_ttl()
returns interval
language sql
immutable
as $function$
  select interval '10 minutes';
$function$;

create or replace function public.issue_phone_code(
  p_user_id uuid,
  p_phone text,
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_expires timestamptz := now() + public.phone_code_ttl();
begin
  -- Any earlier code for this user is void the moment a new one is sent.
  -- Without this, "resend" would leave two valid codes outstanding and double
  -- the guessing surface.
  update public.phone_verifications
  set consumed_at = now()
  where user_id = p_user_id and consumed_at is null;

  insert into public.phone_verifications (user_id, phone, code, expires_at)
  values (p_user_id, p_phone, p_code, v_expires);

  return jsonb_build_object('expires_at', v_expires);
end;
$function$;

create or replace function public.verify_phone_code(
  p_user_id uuid,
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_row public.phone_verifications%rowtype;
begin
  select * into v_row
  from public.phone_verifications
  where user_id = p_user_id and consumed_at is null
  order by created_at desc
  limit 1
  for update;

  if v_row.id is null then
    return jsonb_build_object('verified', false, 'reason', 'no_code');
  end if;

  if v_row.expires_at < now() then
    return jsonb_build_object('verified', false, 'reason', 'expired');
  end if;

  if v_row.attempts >= v_row.max_attempts then
    return jsonb_build_object('verified', false, 'reason', 'too_many_attempts');
  end if;

  -- The attempt is counted before the comparison, and unconditionally. Counting
  -- only failures would let an attacker probe for free by abandoning the
  -- request; counting first means every guess costs one of the five.
  update public.phone_verifications
  set attempts = attempts + 1
  where id = v_row.id;

  if v_row.code <> p_code then
    return jsonb_build_object(
      'verified', false,
      'reason', 'incorrect',
      'attempts_left', v_row.max_attempts - v_row.attempts - 1
    );
  end if;

  update public.phone_verifications
  set consumed_at = now()
  where id = v_row.id;

  -- The phone number is written to `profiles` as well, since that is where the
  -- rest of the app reads it from.
  update public.profiles
  set phone = v_row.phone
  where id = p_user_id;

  insert into public.client_verification_status (
    client_id, phone_verified, phone_verified_at
  )
  values (p_user_id, true, now())
  on conflict (client_id) do update
    set phone_verified = true,
        phone_verified_at = now();

  return jsonb_build_object('verified', true, 'phone', v_row.phone);
end;
$function$;

revoke all on function public.issue_phone_code(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.issue_phone_code(uuid, text, text) to service_role;

revoke all on function public.verify_phone_code(uuid, text)
  from public, anon, authenticated;
grant execute on function public.verify_phone_code(uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- 5. Row level security
-- ---------------------------------------------------------------------------

alter table public.client_verification_status enable row level security;
alter table public.client_saved_addresses enable row level security;
alter table public.phone_verifications enable row level security;

-- A client reads their own trust profile. They do not write it: every column
-- on it is either awarded (`trust_level`), earned (`avg_rating_from_technicians`)
-- or held against them (`no_show_count`), and a self-writable `no_show_count`
-- would let a client erase their own history before every booking.
--
-- The row itself is created by the app at the end of registration through
-- `initialize_client_trust_profile()` below, not by a direct insert.
drop policy if exists "client_verification_select_own" on public.client_verification_status;
create policy "client_verification_select_own"
  on public.client_verification_status for select to authenticated
  using (client_id = auth.uid());

-- A technician needs to see the trust profile of a client they are matched
-- with - that is the entire purpose of the table. Scoped to clients who have
-- actually offered them a job, so it cannot be used to enumerate every client
-- on the platform.
drop policy if exists "client_verification_select_matched" on public.client_verification_status;
create policy "client_verification_select_matched"
  on public.client_verification_status for select to authenticated
  using (
    exists (
      select 1
      from public.job_matches m
      join public.jobs j on j.id = m.job_id
      where m.technician_id = auth.uid()
        and j.client_id = public.client_verification_status.client_id
    )
  );

-- Addresses are wholly the client's own, so all four verbs are theirs.
drop policy if exists "client_addresses_own" on public.client_saved_addresses;
create policy "client_addresses_own"
  on public.client_saved_addresses for all to authenticated
  using (client_id = auth.uid())
  with check (client_id = auth.uid());

-- No policy grants any access to `phone_verifications`. RLS is enabled with no
-- permissive policy for `authenticated`, which denies everything by default -
-- the client can neither read the code nor forge a consumed row. Only the
-- service role, which bypasses RLS, touches this table.
--
-- Belt and braces on the code column itself, in case a future migration adds
-- a read policy for the phone number without noticing what else the row holds.
revoke select (code) on public.phone_verifications from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Initialising the trust profile
-- ---------------------------------------------------------------------------
--
-- Called once, when the client submits for review. Kept as a function rather
-- than an insert policy so the starting values cannot be chosen by the caller:
-- a client who could insert their own row would open at `trusted`.

create or replace function public.initialize_client_trust_profile(
  p_client_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_phone_verified boolean;
begin
  select exists (
    select 1 from public.phone_verifications
    where user_id = p_client_id and consumed_at is not null
  ) into v_phone_verified;

  insert into public.client_verification_status (
    client_id, phone_verified, phone_verified_at, trust_level,
    no_show_count, avg_rating_from_technicians
  )
  values (
    p_client_id,
    v_phone_verified,
    case when v_phone_verified then now() else null end,
    'new',   -- everyone starts here; 'verified' is set when the ID is approved
    0,
    null     -- null, not 0 - see the column comment in section 1
  )
  on conflict (client_id) do update
    set phone_verified = excluded.phone_verified or
                         public.client_verification_status.phone_verified;

  return jsonb_build_object('client_id', p_client_id, 'trust_level', 'new');
end;
$function$;

revoke all on function public.initialize_client_trust_profile(uuid)
  from public, anon, authenticated;
grant execute on function public.initialize_client_trust_profile(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 7. Promote trust level when the ID is approved
-- ---------------------------------------------------------------------------
--
-- `review_identity_verification()` in 20260907000002 flips a client to
-- `active`. This trigger carries that through to the trust profile, so the two
-- cannot disagree - an active client showing `trust_level = 'new'` to every
-- technician would be a bug nobody notices for months.
--
-- 'trusted' is deliberately NOT set here. It is meant to be earned from
-- completed jobs and technician ratings, which is a job for the outcomes
-- aggregator, not for identity review.

create or replace function public.sync_client_trust_level()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.role <> 'client' or new.status is distinct from 'approved' then
    return new;
  end if;

  update public.client_verification_status
  set trust_level = case when trust_level = 'new' then 'verified' else trust_level end
  where client_id = new.user_id;

  return new;
end;
$function$;

drop trigger if exists identity_verifications_sync_trust on public.identity_verifications;
create trigger identity_verifications_sync_trust
  after update on public.identity_verifications
  for each row execute function public.sync_client_trust_level();

-- ---------------------------------------------------------------------------
-- 8. Submitting the whole registration for review (both roles)
-- ---------------------------------------------------------------------------
--
-- Replaces `complete_registration()`, dropped in 20260907000001. The
-- difference is the ending: the old function set `is_verified = true` from a
-- quiz score, activating the account itself. This one can only ever reach
-- `pending_review`, because under mandatory verification a human decides.
--
-- It validates rather than writes. Every step has already saved its own rows
-- as the user went - that is what makes the flow resumable - so all that is
-- left is to confirm nothing required is missing and flip the status.

create or replace function public.submit_registration_for_review(
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_role text;
  v_status text;
  v_has_identity boolean;
  v_spec_count integer;
  v_verified_specs integer;
  v_phone_verified boolean;
  v_has_address boolean;
  v_has_base boolean;
begin
  select role, registration_status into v_role, v_status
  from public.profiles
  where id = p_user_id
  for update;

  if v_role is null then
    raise exception 'No profile for %', p_user_id;
  end if;

  if v_status in ('pending_review', 'active') then
    -- Idempotent: a double submit is a no-op rather than an error, because the
    -- likeliest cause is a retried request on a flaky connection.
    return jsonb_build_object('registration_status', v_status, 'changed', false);
  end if;

  -- The mandatory gate, identical for both roles.
  select exists (
    select 1 from public.identity_verifications
    where user_id = p_user_id and status in ('pending', 'approved')
  ) into v_has_identity;

  if not v_has_identity then
    raise exception 'A government ID and a selfie holding it are required'
      using errcode = '23514';  -- check_violation
  end if;

  if v_role = 'client' then
    select coalesce(phone_verified, false) into v_phone_verified
    from public.client_verification_status where client_id = p_user_id;

    -- Unlike the technician's optional documents, phone verification is a hard
    -- requirement: it is the only channel a technician has to reach a client
    -- who is not at the pinned address when they arrive.
    if not coalesce(v_phone_verified, false) then
      raise exception 'Phone verification is required' using errcode = '23514';
    end if;

    select exists (
      select 1 from public.client_saved_addresses where client_id = p_user_id
    ) into v_has_address;

    if not v_has_address then
      raise exception 'A default address is required' using errcode = '23514';
    end if;
  else
    select count(*), count(*) filter (where verified)
      into v_spec_count, v_verified_specs
    from public.technician_specializations
    where technician_id = p_user_id;

    if v_spec_count = 0 then
      raise exception 'At least one specialisation is required'
        using errcode = '23514';
    end if;

    -- At least one *passed* assessment, not all of them. A technician who
    -- qualified on laptops but is still waiting out a cooldown on printers is
    -- useful to the platform today; the unverified rows simply stay out of the
    -- matching pool until they are passed.
    if v_verified_specs = 0 then
      raise exception 'Pass at least one skill assessment before submitting'
        using errcode = '23514';
    end if;

    select base_latitude is not null and base_longitude is not null
      into v_has_base
    from public.technicians where id = p_user_id;

    if not coalesce(v_has_base, false) then
      raise exception 'A base location is required' using errcode = '23514';
    end if;
  end if;

  update public.profiles
  set registration_status = 'pending_review',
      registration_step = 'review'
  where id = p_user_id;

  return jsonb_build_object('registration_status', 'pending_review', 'changed', true);
end;
$function$;

revoke all on function public.submit_registration_for_review(uuid)
  from public, anon, authenticated;
grant execute on function public.submit_registration_for_review(uuid)
  to service_role;
