/**
 * The fixed labor price for each symptom (2026-11-22), the SERVER's copy.
 *
 * SUGO quotes one fixed labor fee per symptom - the client no longer types a
 * budget. The app shows these prices from `LaborPriceCatalog` in
 * `lib/features/rb_cars/models/labor_price_catalog.dart`; the matcher needs
 * the same figures for the Price fit signal (Stage 2, Table 11), so they are
 * copied here.
 *
 * Change a price in BOTH places. `labor_price.test.ts` reads the Dart file
 * and fails on any code or price that differs, so the two cannot drift
 * silently.
 *
 * The values are the Dart strings exactly, so that comparison is a plain
 * string match. A per-unit fee ("₱800/camera") has no single amount.
 */
export const LABOR_PRICE: Readonly<Record<string, string>> = {
  laptop_slow_or_freezing: "₱500",
  laptop_wont_power_on: "₱750",
  laptop_blue_screen: "₱600",
  laptop_screen_broken: "₱750",
  laptop_battery_not_charging: "₱500",
  laptop_overheating: "₱600",
  laptop_input_dead: "₱600",
  laptop_malware: "₱500",
  laptop_no_os: "₱500",
  laptop_cleaning_tune_up: "₱1,000",
  phone_screen_cracked: "₱400",
  phone_battery_drain: "₱350",
  phone_wont_power_on: "₱600",
  phone_charging_port: "₱450",
  phone_camera_dead: "₱450",
  phone_water_damage: "₱700",
  phone_software_stuck: "₱300",
  phone_audio_dead: "₱400",
  phone_checkup: "₱300",
  appliance_no_power: "₱500",
  appliance_strange_noise: "₱500",
  appliance_not_cooling: "₱700",
  appliance_water_leak: "₱600",
  appliance_electrical_fault: "₱700",
  appliance_part_replacement: "₱500",
  appliance_aircon_cleaning: "₱800",
  appliance_checkup: "₱500",
  appliance_aircon_install_window: "₱1,500",
  appliance_aircon_install_split: "₱3,500",
  appliance_tv_mounting: "₱800",
  appliance_washer_install: "₱500",
  network_no_internet: "₱350",
  network_weak_signal: "₱500",
  network_router_dead: "₱500",
  network_new_install: "₱800",
  network_checkup: "₱500",
  network_device_wont_connect: "₱300",
  cctv_new_install: "₱800/camera",
  cctv_no_video: "₱600",
  cctv_offline: "₱400",
  cctv_recorder_dead: "₱700",
  cctv_night_vision: "₱500",
  cctv_cable_damage: "₱600",
  cctv_expand_system: "₱800/camera",
};

/**
 * The urgent fee's share of the labor: 20%, the same rule as
 * `LaborPriceCatalog.urgentRate` (₱600 labor -> ₱120 urgent fee).
 */
export const URGENT_FEE_RATE = 0.20;

/**
 * The labor fee in whole pesos, or null when the symptom has no catalogue
 * price ("I am not sure") or the fee is per unit ("₱800/camera").
 */
export function laborAmount(symptomCode: string | null | undefined): number | null {
  if (!symptomCode) return null;
  const fee = LABOR_PRICE[symptomCode];
  if (fee === undefined || fee.includes("/")) return null;
  const amount = Number.parseInt(fee.replace(/[^0-9]/g, ""), 10);
  return Number.isNaN(amount) ? null : amount;
}

/** 20% of [labor], rounded to the peso - `LaborPriceCatalog.urgentFee`. */
export function urgentFee(labor: number): number {
  return Math.round(labor * URGENT_FEE_RATE);
}

/**
 * What the technician is paid for the work itself: the labor fee, plus the
 * urgent fee when the job is needed today. Null when there is no flat price.
 *
 * The travel or delivery fee is left out on purpose. It pays for the trip,
 * not the repair, and the trip is already scored by Travel burden.
 */
export function fixedJobPrice(
  symptomCode: string | null | undefined,
  urgency: string | null | undefined,
): number | null {
  const labor = laborAmount(symptomCode);
  if (labor === null) return null;
  return urgency === "need_today" ? labor + urgentFee(labor) : labor;
}
