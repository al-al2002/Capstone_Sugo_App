-- SUGO: routers and CCTV become declarable devices, with their own assessment
--
-- The `network` job category has been the odd one out since the specialisation
-- catalogue was introduced. `job_device_candidates()` returned an empty array
-- for it, so:
--
--   * a client posting a network job was offered no device and no brand, and
--   * every candidate fell to the device-only rung of the Stage 1 ladder,
--     because no technician could declare a matching specialisation at all.
--
-- Two devices close that gap - `router` and `cctv` - and one assessment track
-- covers them. A camera system is a network before it is a camera: the same
-- knowledge of cabling, addressing and PoE serves both, which is exactly the
-- grouping rule the other tracks already follow.
--
-- No table changes. `technician_specializations.device_type` is plain `text`
-- with no check, and both devices sit under the existing `it_device` category,
-- so the constraint is untouched.

-- ---------------------------------------------------------------------------
-- 1. Device -> assessment track
-- ---------------------------------------------------------------------------
--
-- Mirrored by `AssessmentTrack` in the Flutter catalogue, and pinned by
-- `test/features/onboarding/registration_gate_test.dart`.

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
    when 'router'          then 'network_surveillance'
    when 'cctv'            then 'network_surveillance'
    else p_device_type
  end;
$function$;

comment on function public.assessment_track(text) is
  'Device type -> assessment track. One assessment covers every device and '
  'brand in a track. Mirrored by AssessmentTrack in the Flutter catalogue.';

-- ---------------------------------------------------------------------------
-- 2. Coarse job category -> the specialisations that can serve it
-- ---------------------------------------------------------------------------
--
-- `jobs.device_type` is checked against ('laptop','phone','appliance',
-- 'network') and that constraint is not moving, so CCTV is not a fifth
-- category. It is a *device_detail* under `network`, which is the same shape
-- `desktop` already has under `laptop`.

create or replace function public.job_device_candidates(
  p_device_type text,
  p_device_detail text default null
)
returns text[]
language sql
immutable
as $function$
  select case
    when coalesce(trim(p_device_detail), '') <> '' then array[p_device_detail]
    when p_device_type = 'laptop'    then array['laptop', 'desktop']
    when p_device_type = 'phone'     then array['smartphone', 'tablet']
    when p_device_type = 'appliance' then array[
      'aircon', 'refrigerator', 'washing_machine', 'television', 'microwave'
    ]
    when p_device_type = 'network'   then array['router', 'cctv']
    else array[]::text[]
  end;
$function$;

comment on function public.job_device_candidates(text, text) is
  'Maps a job onto the technician_specializations.device_type values that can '
  'serve it. Bridges the coarse jobs vocabulary and the fine specialisation '
  'one so a brand/device filter does not silently exclude most technicians.';

-- ---------------------------------------------------------------------------
-- 3. The question bank
-- ---------------------------------------------------------------------------
--
-- Ten multiple-choice questions, same shape as the existing banks. Guarded by
-- the same `not exists` so re-running cannot duplicate the set.
--
-- The questions test diagnosis, not product trivia: which end of a link to
-- suspect, what a symptom rules out, and the two safety facts that matter when
-- somebody is up a ladder near mains wiring.

insert into public.assessment_questions
  (specialization, question, choices, correct_choice_index)
select * from (values
  (
    'network_surveillance',
    'A client has no internet. The router shows a red or orange internet light. What does that point at first?',
    '["A faulty network cable inside the house","The link between the router and the provider, not the home network","Too many devices connected at once","A failing power adapter"]'::jsonb,
    1
  ),
  (
    'network_surveillance',
    'Wi-Fi is strong beside the router but drops in the far bedroom. What is the correct first response?',
    '["Replace the router immediately","Measure signal in the rooms that fail and consider placement or an access point","Raise the transmit power past the legal limit","Ask the client to use mobile data there"]'::jsonb,
    1
  ),
  (
    'network_surveillance',
    'Devices connect to the Wi-Fi but no page loads, and the router itself reaches the internet. Most likely cause?',
    '["The Wi-Fi password is wrong","DNS or DHCP misconfiguration on the network","The antenna is broken","The provider is down"]'::jsonb,
    1
  ),
  (
    'network_surveillance',
    'A PoE IP camera will not power on, and the same cable works on a laptop. What do you check next?',
    '["The camera lens","Whether the switch port actually supplies PoE and at the wattage the camera needs","The recording schedule","The client Wi-Fi password"]'::jsonb,
    1
  ),
  (
    'network_surveillance',
    'What is the practical maximum run for a single Ethernet cable before you need a switch or extender?',
    '["25 metres","50 metres","100 metres","300 metres"]'::jsonb,
    2
  ),
  (
    'network_surveillance',
    'Several cameras show at night but the image is washed out and white. Most likely cause?',
    '["The lens is cracked","Infrared light reflecting off a nearby wall, glass or the housing","The recorder hard drive is full","The cable is too long"]'::jsonb,
    1
  ),
  (
    'network_surveillance',
    'A client says their recorder stopped keeping older footage. What do you inspect first?',
    '["The camera resolution setting","The recorder hard drive health and the overwrite or retention setting","The router firmware","The power adapter"]'::jsonb,
    1
  ),
  (
    'network_surveillance',
    'A client wants to view their cameras from outside the house. What is the safe way to set that up?',
    '["Forward the recorder port to the internet with the default password","Use the manufacturer cloud or a VPN, and change every default credential","Put the recorder in the router DMZ","Share the admin password over text"]'::jsonb,
    1
  ),
  (
    'network_surveillance',
    'You are installing a camera on an exterior wall near an existing mains line. What comes first?',
    '["Drill and run the cable, then isolate the circuit","Isolate the circuit at the breaker and confirm it is dead before drilling","Work live but wear gloves","Ask the client to hold the ladder"]'::jsonb,
    1
  ),
  (
    'network_surveillance',
    'A camera keeps dropping off the network at random times each day. Which is the most useful thing to check?',
    '["The camera brand","Whether it holds a stable address, and the power and cable at the times it drops","The colour of the housing","The number of cameras installed"]'::jsonb,
    1
  )
) as seed(specialization, question, choices, correct_choice_index)
where not exists (
  select 1 from public.assessment_questions
  where specialization = 'network_surveillance'
);
