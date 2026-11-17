-- SUGO: shop repair delivery option and fee (2026-11-16)
--
-- A shop repair (`service_path = 'pickup'`) now asks the client how the unit
-- gets to and from the shop:
--
--   self      "I'll bring it / pick it up myself"   fee PHP 0
--   delivery  "Shop pickup/delivery"                fee by distance
--
-- ## The columns (approved by the user, 2026-11-16)
--
--   delivery_option  self | delivery - chosen when posting, and confirmable in
--                    the booking dialog. Null on every non-shop job, and on
--                    shop jobs from before today (they behave as delivery,
--                    which is what they always were).
--   distance_km      straight-line km from the job pin to the CHOSEN
--                    technician's shop (shop_*, else base_*), 2 dp. Written
--                    by `job-response` when the client sends the request.
--   delivery_fee     whole pesos. 0 for self; for delivery the distance is
--                    rounded UP to a whole km, then PHP 50 up to 3 km, plus
--                    PHP 15 for each km after that.
--
-- `service_type` is not a new column: it is the existing `service_path`
-- (home_service | pickup | it_community).
--
-- ## Who writes what
--
-- The client writes `delivery_option` (posting inserts it; edits go through
-- `job-response`, whose whitelist gains it). `distance_km` and
-- `delivery_fee` are written ONLY by `job-response` on select, from the
-- technician's shop location, which the client never sees before booking.
-- The client cannot set their own fee.
--
-- No RLS change: `jobs` already allows the client's insert, and the server
-- writes on the service role.

alter table public.jobs
  add column if not exists delivery_option text
    check (delivery_option in ('self', 'delivery')),
  add column if not exists distance_km numeric(6, 2)
    check (distance_km >= 0),
  add column if not exists delivery_fee integer
    check (delivery_fee >= 0);

-- A delivery option only means something on a shop repair. A job edited or
-- converted to home service or the community must drop it - the app sends
-- null, and this makes the database insist.
alter table public.jobs drop constraint if exists jobs_delivery_option_needs_shop;
alter table public.jobs add constraint jobs_delivery_option_needs_shop
  check (delivery_option is null or service_path = 'pickup');

-- "Bring it myself" costs nothing; a fee on a self job is a bug.
alter table public.jobs drop constraint if exists jobs_self_is_free;
alter table public.jobs add constraint jobs_self_is_free
  check (delivery_option is distinct from 'self' or coalesce(delivery_fee, 0) = 0);

comment on column public.jobs.delivery_option is
  'Shop repair only: self = client brings and collects it (fee 0); delivery = shop pickup and delivery (fee by distance). Null otherwise.';
comment on column public.jobs.distance_km is
  'Straight-line km from the job to the chosen technician''s shop, written by job-response on select.';
comment on column public.jobs.delivery_fee is
  'PHP. 0 for self; delivery = 50 up to 3 km, then +15 per km (distance rounded up). Written by job-response on select.';
