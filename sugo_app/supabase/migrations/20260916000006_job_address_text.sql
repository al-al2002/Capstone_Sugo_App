-- SUGO: a job remembers WHERE it is, not just its coordinates
--
-- `jobs` stored latitude and longitude and nothing else, so every screen that
-- showed a job's location printed the raw pair:
--
--   7.07361, 125.61278
--
-- That is unreadable to a client checking their own booking, and close to
-- useless to a technician deciding whether to accept one. Both of them think in
-- places, not decimal degrees.
--
-- ## Why a column and not a lookup
--
-- The alternative was reverse-geocoding on display. That would mean a Nominatim
-- request every time anybody opened a job - against a public instance whose
-- policy is one request per second and whose penalty is an IP block, as
-- documented at length in `GeocodingService`. It would also make a list of
-- bookings issue one network call per row.
--
-- The address is already known at the moment it matters: the client either
-- searched for it, used their GPS, or tapped a pin that was reverse-geocoded
-- once. Capturing that string is free; rediscovering it later is not.
--
-- ## Why free text
--
-- Exactly the reasoning `client_saved_addresses.address_text` gives in
-- 20260907000004: Philippine addresses do not reliably decompose into
-- street/barangay/city columns, and the technician needs the string a human
-- would recognise rather than a normalised one.
--
-- ## Nullable, deliberately
--
-- A job posted while Nominatim was unreachable still has to be postable. Null
-- means "we never resolved a name", and every display falls back to the
-- coordinates - which is what all of them printed before this migration, so the
-- fallback is already proven. Existing rows keep working untouched.

alter table public.jobs
  add column if not exists address_text text;

comment on column public.jobs.address_text is
  'Human-readable address for the job location, captured when the client set '
  'the pin. Null when it could not be resolved; callers fall back to the '
  'latitude/longitude pair.';
