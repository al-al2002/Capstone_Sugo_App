-- SUGO: one assessment per skill, not per brand
--
-- ## The problem
--
-- Assessments were keyed to a `technician_specializations` row, and there is
-- one of those per (device_type, brand) pair. A technician who repairs laptops
-- and desktops for Apple, Dell and HP therefore had SIX assessments queued -
-- and `_questionBankFor()` already handed all six the *same* `laptop_repair`
-- question bank. They would answer the identical ten questions six times.
--
-- Worse, only `appliance_repair` was ever seeded. `laptop_repair` and
-- `phone_repair` had no questions at all, so `fetchQuestions` threw "No
-- questions are available" and a laptop technician could never pass anything,
-- could never satisfy `submit_registration_for_review()`, and could never
-- finish registering. A dead end, not just an annoyance.
--
-- ## The fix: tracks
--
-- Competence is grouped by what the repair actually is. Passing one track
-- verifies every specialisation the technician declared inside it, whatever
-- the brand.
--
--   computer_repair    laptop, desktop
--   mobile_repair      smartphone, tablet
--   printer_repair     printer
--   refrigeration      aircon, refrigerator
--   laundry_appliance  washing machine
--   home_electronics   television, microwave
--
-- Worst case drops from 10 devices x 7 brands = 70 assessments to 6.
--
-- ## Why brand is not assessed
--
-- The thing being measured is whether someone can diagnose a compressor or a
-- dead mainboard, and that does not change between Samsung and LG. Brand still
-- matters - it is what lets RB-CARS match a client with an LG aircon to
-- somebody who declared LG - but it is a *matching* signal, not a competency
-- one. Testing it would mean brand trivia, not skill.
--
-- ## Why these groupings
--
-- Each track is one body of knowledge and one set of hazards:
--
--   computer_repair   - boards, storage, PSUs, operating systems
--   mobile_repair     - screens, batteries, charge ports, water damage
--   printer_repair    - a mechanical paper path plus drivers; genuinely its own
--   refrigeration     - sealed systems, compressors, refrigerant. An aircon and
--                       a refrigerator are the same machine in a different box
--   laundry_appliance - motors, pumps, belts, water and drainage
--   home_electronics  - mains electronics with dangerous stored charge

-- ---------------------------------------------------------------------------
-- 1. The mapping, in one place
-- ---------------------------------------------------------------------------
--
-- IMMUTABLE so it can be used in an expression index. Kept as a function
-- rather than a lookup table so the rule is greppable and versioned with the
-- migrations - and because it is read by a trigger on every insert.
--
-- An unknown device falls back to its own name as the track. That keeps a
-- device added to the Flutter catalogue but forgotten here from silently
-- joining somebody else's track; it simply gets a track of its own with no
-- questions, which surfaces loudly instead of quietly mis-verifying.

create or replace function public.assessment_track(p_device_type text)
returns text
language sql
immutable
as $function$
  select case p_device_type
    when 'laptop'          then 'computer_repair'
    when 'desktop'         then 'computer_repair'
    when 'smartphone'      then 'mobile_repair'
    when 'tablet'          then 'mobile_repair'
    when 'printer'         then 'printer_repair'
    when 'aircon'          then 'refrigeration'
    when 'refrigerator'    then 'refrigeration'
    when 'washing_machine' then 'laundry_appliance'
    when 'television'      then 'home_electronics'
    when 'microwave'       then 'home_electronics'
    else p_device_type
  end;
$function$;

comment on function public.assessment_track(text) is
  'Device type -> assessment track. One assessment covers every device and '
  'brand in a track. Mirrored by AssessmentTrack in the Flutter catalogue.';

-- ---------------------------------------------------------------------------
-- 2. Store the track on each row
-- ---------------------------------------------------------------------------
--
-- A plain column maintained by a trigger, NOT a generated column. Postgres
-- will not let you replace a function a generated column depends on, so the
-- grouping above would be frozen for ever; with a trigger, changing the
-- mapping is one UPDATE away.

alter table public.technician_specializations
  add column if not exists track text;

alter table public.technician_assessment_results
  add column if not exists track text;

create or replace function public.set_specialization_track()
returns trigger
language plpgsql
as $function$
begin
  new.track := public.assessment_track(new.device_type);
  return new;
end;
$function$;

drop trigger if exists technician_specializations_set_track
  on public.technician_specializations;
create trigger technician_specializations_set_track
  before insert or update of device_type on public.technician_specializations
  for each row execute function public.set_specialization_track();

-- Backfill anything that predates the column.
update public.technician_specializations
set track = public.assessment_track(device_type)
where track is null;

update public.technician_assessment_results r
set track = s.track
from public.technician_specializations s
where s.id = r.specialization_id and r.track is null;

create index if not exists idx_specializations_track
  on public.technician_specializations (technician_id, track);

create index if not exists idx_assessment_results_track
  on public.technician_assessment_results (technician_id, track, taken_at desc);

-- ---------------------------------------------------------------------------
-- 3. Scoring a track
-- ---------------------------------------------------------------------------
--
-- Replaces the per-specialisation version from 20260907000003. The important
-- change is the last step: a pass verifies EVERY specialisation the technician
-- holds in that track, so one sitting covers all their brands.
--
-- `specialization_id` on the result row is kept and set to one of the rows in
-- the track, so the existing foreign key and the cascade still work. The track
-- is what the logic actually keys on.

drop function if exists public.record_assessment_result(uuid, uuid, numeric);

create or replace function public.record_assessment_result(
  p_technician_id uuid,
  p_track text,
  p_score numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_last_attempt timestamptz;
  v_last_passed boolean;
  v_attempt integer;
  v_level text;
  v_passed boolean;
  v_cooldown interval := public.assessment_retake_cooldown();
  v_spec_id uuid;
  v_verified_count integer;
begin
  -- The technician must actually hold a specialisation in this track. Without
  -- this a caller could pass any track string and qualify for work they never
  -- declared.
  select id into v_spec_id
  from public.technician_specializations
  where technician_id = p_technician_id and track = p_track
  order by created_at
  limit 1;

  if v_spec_id is null then
    raise exception 'No specialisation in track % for this technician', p_track;
  end if;

  select taken_at, passed into v_last_attempt, v_last_passed
  from public.technician_assessment_results
  where technician_id = p_technician_id and track = p_track
  order by taken_at desc
  limit 1;

  if v_last_passed then
    raise exception 'This assessment has already been passed';
  end if;

  if v_last_attempt is not null and v_last_attempt + v_cooldown > now() then
    raise exception 'Retake available at %', v_last_attempt + v_cooldown
      using errcode = '55000';
  end if;

  select coalesce(max(attempt_number), 0) + 1 into v_attempt
  from public.technician_assessment_results
  where technician_id = p_technician_id and track = p_track;

  v_level := public.assessment_skill_level(p_score);
  v_passed := v_level is not null;

  insert into public.technician_assessment_results (
    technician_id, specialization_id, track, score, passed, attempt_number
  )
  values (p_technician_id, v_spec_id, p_track, p_score, v_passed, v_attempt);

  if v_passed then
    -- The whole point of this migration: one pass, every brand in the track.
    update public.technician_specializations
    set skill_level = v_level,
        verified = true
    where technician_id = p_technician_id and track = p_track;

    get diagnostics v_verified_count = row_count;
  else
    v_verified_count := 0;
  end if;

  return jsonb_build_object(
    'passed', v_passed,
    'score', p_score,
    'track', p_track,
    'skill_level', v_level,
    'attempt_number', v_attempt,
    'specializations_verified', v_verified_count,
    'retake_available_at',
      case when v_passed then null else now() + v_cooldown end
  );
end;
$function$;

revoke all on function public.record_assessment_result(uuid, text, numeric)
  from public, anon, authenticated;
grant execute on function public.record_assessment_result(uuid, text, numeric)
  to service_role;

-- ---------------------------------------------------------------------------
-- 4. Question banks for every track
-- ---------------------------------------------------------------------------
--
-- Ten questions each, so the 70% pass mark needs 7 correct and the 90% expert
-- band needs 9. Fewer questions would make those bands coarse - with eight,
-- "expert" would demand a perfect paper.
--
-- These are placeholders in the sense that a real deployment would have them
-- written and reviewed by working technicians. They are not placeholders in
-- the sense of being fake: each one has a single defensible answer drawn from
-- ordinary repair practice, so the flow can be demonstrated honestly.
--
-- The legacy `appliance_repair` bank from 20260906000001 is deliberately left
-- alone. The older onboarding flow still selects it by name.
--
-- Seeded only when a track is empty, so re-running never duplicates.

insert into public.assessment_questions
  (specialization, question, choices, correct_choice_index)
select * from (values

  -- ------------------------------------------------------ computer_repair
  ('computer_repair','A laptop powers on but the screen stays black, and an external monitor works. What do you check first?',
   '["The RAM modules","The display cable, backlight and panel","The hard drive","The operating system"]'::jsonb,1),
  ('computer_repair','A desktop gives no display and beeps repeatedly at power-on. What is that telling you?',
   '["The PSU is fine","A POST error code, usually RAM or GPU","The CPU fan is dirty","Windows is corrupted"]'::jsonb,1),
  ('computer_repair','Before opening any computer you should:',
   '["Run a virus scan","Unplug it, hold the power button to drain, and ground yourself","Back up the BIOS","Remove the CPU"]'::jsonb,1),
  ('computer_repair','A laptop runs hot and throttles under load. Most likely cause?',
   '["Failing hard drive","Dust-clogged heatsink and dried thermal paste","Insufficient RAM","A weak battery"]'::jsonb,1),
  ('computer_repair','Which best indicates a failing mechanical hard drive?',
   '["A blue login screen","Clicking noises and SMART reallocated-sector warnings","A loud fan","A dim display"]'::jsonb,1),
  ('computer_repair','A PC restarts randomly under heavy load. First suspect?',
   '["The keyboard","An underpowered or failing PSU, or overheating","The monitor cable","The mouse driver"]'::jsonb,1),
  ('computer_repair','What does it mean when a laptop only runs while plugged in?',
   '["The screen is failing","The battery or its charging circuit is faulty","The CPU is throttled","The RAM is loose"]'::jsonb,1),
  ('computer_repair','Safest first step when a customer reports data loss?',
   '["Reinstall the OS immediately","Stop writing to the drive and image it before anything else","Run disk cleanup","Defragment the drive"]'::jsonb,1),
  ('computer_repair','A desktop does not power on at all - no fans, no lights. What do you test first?',
   '["The GPU","Mains outlet, PSU switch, and the PSU itself","The sound card","The RAM"]'::jsonb,1),
  ('computer_repair','Why is thermal paste replaced when reseating a heatsink?',
   '["To glue the heatsink down","The old layer is disturbed and no longer transfers heat evenly","To silence the fan","To insulate the CPU electrically"]'::jsonb,1),

  -- -------------------------------------------------------- mobile_repair
  ('mobile_repair','A phone screen shows an image but does not respond to touch. What failed?',
   '["The battery","The digitiser layer","The charging port","The speaker"]'::jsonb,1),
  ('mobile_repair','A phone charges only when the cable is held at an angle. Most likely cause?',
   '["A dead battery","A worn or lint-blocked charging port","Faulty RAM","A cracked screen"]'::jsonb,1),
  ('mobile_repair','A phone has been in water. What should you NOT do?',
   '["Power it off","Charge it or power it on to test","Open it and dry it","Remove the battery if possible"]'::jsonb,1),
  ('mobile_repair','A swollen battery must be:',
   '["Punctured to release gas","Removed carefully and disposed of properly; never punctured","Charged fully","Refitted with tape"]'::jsonb,1),
  ('mobile_repair','A phone gets very hot and drains fast while idle. First check?',
   '["The screen brightness only","Battery health and a rogue background app or failing charge IC","The ringtone","The SIM card"]'::jsonb,1),
  ('mobile_repair','Why is a heat gun or heat pad used when opening a modern phone?',
   '["To dry the board","To soften the adhesive holding the screen or back glass","To test the battery","To reflow the CPU"]'::jsonb,1),
  ('mobile_repair','A tablet shows the charging icon but the percentage never rises. Likely cause?',
   '["The display is broken","A failed battery or charging IC","The volume button","A software theme"]'::jsonb,1),
  ('mobile_repair','After a screen replacement the proximity sensor stops working. Most likely reason?',
   '["The battery is low","The sensor bracket or mesh was not transferred to the new screen","The SIM is unseated","The OS needs reinstalling"]'::jsonb,1),
  ('mobile_repair','What should you always do before any phone repair?',
   '["Factory reset it","Back up if possible, and record the device''s condition and IMEI","Remove the screen protector","Charge it to 100%"]'::jsonb,1),
  ('mobile_repair','A phone boots to the logo then restarts, repeatedly. This is:',
   '["Normal after charging","A boot loop - firmware corruption or a hardware fault","A dead screen","A SIM error"]'::jsonb,1),

  -- ------------------------------------------------------- printer_repair
  ('printer_repair','An inkjet prints with horizontal banding or missing colours. First step?',
   '["Replace the mainboard","Run a nozzle check and head cleaning","Reinstall Windows","Replace the paper feed roller"]'::jsonb,1),
  ('printer_repair','A laser printer output smudges when rubbed. Which part is at fault?',
   '["The toner cartridge","The fuser assembly","The paper tray","The USB cable"]'::jsonb,1),
  ('printer_repair','Repeated paper jams from the same tray usually point to:',
   '["A driver problem","Worn pickup rollers or a wrong paper setting","Low toner","A network fault"]'::jsonb,1),
  ('printer_repair','A printer is offline but powered on and networked. What do you check?',
   '["The fuser","IP address, connection and the print spooler","The toner level","The scanner glass"]'::jsonb,1),
  ('printer_repair','Vertical lines on every scanned page indicate:',
   '["Low ink","Dirt or a scratch on the scanner glass or ADF strip","A bad driver","A paper jam"]'::jsonb,1),
  ('printer_repair','Why must you avoid touching a laser printer''s drum unit surface?',
   '["It is hot","Fingerprints and light damage the photosensitive coating","It is electrically live","It voids the paper warranty"]'::jsonb,1),
  ('printer_repair','A continuous-ink printer suddenly prints faint pages. First check?',
   '["The power supply","Ink levels, air in the tubing, and the damper","The paper weight","The Wi-Fi signal"]'::jsonb,1),
  ('printer_repair','Which is the correct safety step before servicing a laser printer''s fuser?',
   '["Nothing, it is safe","Power off and let it cool - the fuser runs at around 200C","Spray it with cleaner","Remove the toner first"]'::jsonb,1),
  ('printer_repair','A printer prints garbled characters. Most likely cause?',
   '["A faulty fuser","The wrong or corrupted printer driver","A dirty drum","Low paper"]'::jsonb,1),
  ('printer_repair','Waste ink pad or maintenance box counters exist to:',
   '["Sell more ink","Track absorbed waste ink so the pad is replaced before it overflows","Measure page count for billing","Control print speed"]'::jsonb,1),

  -- -------------------------------------------------------- refrigeration
  ('refrigeration','A window-type aircon runs but does not cool. Which do you check first?',
   '["Compressor windings","Air filter and evaporator coil for blockage","Remote batteries","Wall outlet voltage"]'::jsonb,1),
  ('refrigeration','A refrigerator is cold in the freezer but warm in the fridge compartment. Most likely cause?',
   '["A faulty freezer door seal","Blocked evaporator fan or defrost failure","Thermostat set too low","An overloaded circuit"]'::jsonb,1),
  ('refrigeration','Ice building up on aircon copper piping usually indicates:',
   '["Too much refrigerant","Restricted airflow or a low refrigerant charge","A loose terminal","Normal humid-weather operation"]'::jsonb,1),
  ('refrigeration','What does the capacitor do in a single-phase compressor motor?',
   '["Stores refrigerant","Provides the phase shift needed for starting torque","Filters water","Sets the temperature"]'::jsonb,1),
  ('refrigeration','Why must a capacitor be discharged before servicing?',
   '["It may leak refrigerant","It can hold a dangerous charge after unplugging","It resets the timer","It affects the warranty"]'::jsonb,1),
  ('refrigeration','A fridge compressor runs constantly and never cycles off. Likely cause?',
   '["The light bulb is on","Poor door seal, low refrigerant, or dirty condenser coils","Too little food inside","The ice maker is off"]'::jsonb,1),
  ('refrigeration','Oily residue around a pipe joint on a split unit suggests:',
   '["Normal lubrication","A refrigerant leak at that joint","Condensation","Excess charge"]'::jsonb,1),
  ('refrigeration','Which instrument reads suction and discharge pressure on a sealed system?',
   '["A multimeter","A manifold gauge set","A clamp meter","An infrared thermometer"]'::jsonb,1),
  ('refrigeration','Why is a system evacuated with a vacuum pump before charging?',
   '["To cool the pipes","To remove moisture and non-condensable air","To test the compressor","To flush the oil"]'::jsonb,1),
  ('refrigeration','Water pooling inside the bottom of a refrigerator usually means:',
   '["The compressor failed","A blocked defrost drain line","Too much refrigerant","A bad thermostat"]'::jsonb,1),

  -- ---------------------------------------------------- laundry_appliance
  ('laundry_appliance','A washing machine drains but will not spin. Most likely cause?',
   '["Clogged inlet valve","Worn drive belt or a faulty lid switch","Wrong detergent","Low water pressure"]'::jsonb,1),
  ('laundry_appliance','A washer fills very slowly or not at all. What do you check first?',
   '["The drive motor","Tap, inlet hose and the inlet valve filter screens","The drain pump","The door seal"]'::jsonb,1),
  ('laundry_appliance','A machine walks across the floor during spin. Cause?',
   '["Too much detergent","An unbalanced load or unlevelled feet and worn suspension","Water too hot","A blocked filter"]'::jsonb,1),
  ('laundry_appliance','A washer will not drain and water stays in the drum. First check?',
   '["The timer","The drain pump filter and hose for blockage","The heating element","The door hinge"]'::jsonb,1),
  ('laundry_appliance','A loud grinding noise during spin most often means:',
   '["Too much detergent","Failed drum bearings or an object in the outer tub","Low water pressure","A software fault"]'::jsonb,1),
  ('laundry_appliance','Before working on any washing machine you must:',
   '["Run a rinse cycle","Unplug it and shut off and drain the water supply","Remove the drum","Level the feet"]'::jsonb,1),
  ('laundry_appliance','The door of a front loader will not unlock after a cycle. Likely cause?',
   '["A dead motor","A faulty door lock assembly or water still in the drum","Wrong detergent","A blocked vent"]'::jsonb,1),
  ('laundry_appliance','Clothes come out still soaking after a full spin. Most likely?',
   '["Too little detergent","Restricted drainage or a failing pump, so spin is cut short","Water too cold","An open lid switch only"]'::jsonb,1),
  ('laundry_appliance','A persistent musty smell in a front loader is usually caused by:',
   '["Hard water only","Residue and moisture trapped in the door gasket and dispenser","A faulty motor","A bent drum"]'::jsonb,1),
  ('laundry_appliance','Which tool checks continuity of a lid switch or door lock?',
   '["A manifold gauge","A multimeter on the ohms setting","An infrared thermometer","A clamp meter on amps"]'::jsonb,1),

  -- ----------------------------------------------------- home_electronics
  ('home_electronics','A microwave runs but does not heat. Which component is the usual suspect?',
   '["The turntable motor","The magnetron or high-voltage diode","The door hinge","The panel backlight"]'::jsonb,1),
  ('home_electronics','Why is a microwave dangerous to service even when unplugged?',
   '["The magnetron stays hot","The high-voltage capacitor can hold a lethal charge","The turntable spins","The door is heavy"]'::jsonb,1),
  ('home_electronics','A TV has sound but no picture, and a torch reveals a faint image. What failed?',
   '["The main board","The backlight LEDs or their driver","The speakers","The remote"]'::jsonb,1),
  ('home_electronics','A TV shows no power light at all. First check?',
   '["The panel","Mains supply, then the standby rail on the power board","The HDMI cable","The firmware"]'::jsonb,1),
  ('home_electronics','Bulging or vented capacitors on a power board indicate:',
   '["Normal wear, safe to leave","Failed capacitors that must be replaced","A cooling problem only","A software fault"]'::jsonb,1),
  ('home_electronics','Vertical coloured lines fixed on a TV screen usually mean:',
   '["A bad HDMI cable","A panel or T-CON board fault","Wrong picture mode","A weak antenna"]'::jsonb,1),
  ('home_electronics','A microwave sparks inside during use. Most likely cause?',
   '["Too much food","A damaged waveguide cover or burnt cavity paint","The turntable","A low voltage supply"]'::jsonb,1),
  ('home_electronics','What is the correct way to discharge a high-voltage capacitor?',
   '["Short it with a screwdriver","Use an insulated resistor across the terminals, then confirm with a meter","Leave it overnight only","Touch both terminals"]'::jsonb,1),
  ('home_electronics','A TV restarts in a loop shortly after power-on. Common cause?',
   '["A dirty screen","Failing power-board capacitors or a shorted backlight string","A weak signal","Wrong aspect ratio"]'::jsonb,1),
  ('home_electronics','A microwave stops the moment the door is opened because of:',
   '["The timer","Interlock switches that cut power for safety","The magnetron cooling","The turntable sensor"]'::jsonb,1)

) as seed(specialization, question, choices, correct_choice_index)
where not exists (
  select 1 from public.assessment_questions existing
  where existing.specialization = seed.specialization
);

-- ---------------------------------------------------------------------------
-- 5. Which tracks a technician still owes
-- ---------------------------------------------------------------------------
--
-- One row per (technician, track) with the attempt history folded in, so the
-- app can render the assessment list in a single read instead of pairing two
-- queries in Dart.

create or replace view public.technician_assessment_tracks as
select
  s.technician_id,
  s.track,
  count(*)                                      as specialization_count,
  count(*) filter (where s.verified)            as verified_count,
  bool_or(s.verified)                           as passed,
  max(s.skill_level) filter (where s.verified)  as skill_level,
  (
    select r.score from public.technician_assessment_results r
    where r.technician_id = s.technician_id and r.track = s.track
    order by r.taken_at desc limit 1
  )                                             as last_score,
  (
    select r.taken_at from public.technician_assessment_results r
    where r.technician_id = s.technician_id and r.track = s.track
    order by r.taken_at desc limit 1
  )                                             as last_attempt_at,
  (
    select count(*) from public.technician_assessment_results r
    where r.technician_id = s.technician_id and r.track = s.track
  )                                             as attempt_count
from public.technician_specializations s
group by s.technician_id, s.track;

comment on view public.technician_assessment_tracks is
  'One row per technician per assessment track. Passing a track verifies every '
  'declared brand inside it, so this is what the app lists rather than the '
  'individual specialisation rows.';

alter view public.technician_assessment_tracks set (security_invoker = on);

grant select on public.technician_assessment_tracks to authenticated;
