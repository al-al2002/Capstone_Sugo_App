/**
 * OpenWeatherMap current-conditions client.
 *
 * Same shape and same reasoning as the TomTom client: the key is a Supabase
 * secret, the call happens once per job at the client's coordinate, and any
 * failure returns `available: false` so Stage 2 redistributes the weight
 * instead of penalising everyone equally.
 *
 * Rain is the ordinary reason a Davao home-service visit slips, which is why
 * this is a scoring input and not decoration.
 */
import {
  EXTERNAL_API_TIMEOUT_MS,
  WEATHER_SEVERITY,
} from "../scoring/constants.ts";
import type { WeatherContext } from "../scoring/types.ts";

const UNAVAILABLE: WeatherContext = {
  available: false,
  condition: null,
  description: null,
  tempC: null,
  severity: null,
  label: null,
};

interface WeatherResponse {
  weather?: Array<{ id?: number; main?: string; description?: string }>;
  main?: { temp?: number; humidity?: number };
  name?: string;
}

/**
 * Maps an OpenWeatherMap condition id to a 0..1 severity.
 *
 * The id groups are documented at
 * <https://openweathermap.org/weather-conditions>. 2xx storms are the worst
 * case for a motorcycle-borne technician; 800 is clear sky.
 */
export function severityForConditionId(id: number | undefined): number {
  if (id === undefined) return WEATHER_SEVERITY.unknown;

  if (id >= 200 && id < 300) return WEATHER_SEVERITY.thunderstorm;
  if (id >= 300 && id < 400) return WEATHER_SEVERITY.drizzle;
  if (id >= 500 && id < 600) {
    // 502-504 heavy/extreme, 511 freezing, 522/531 heavy showers.
    const heavy = [502, 503, 504, 511, 522, 531];
    return heavy.includes(id) ? WEATHER_SEVERITY.heavyRain : WEATHER_SEVERITY.rain;
  }
  if (id >= 600 && id < 700) return WEATHER_SEVERITY.snow;
  if (id >= 700 && id < 800) return WEATHER_SEVERITY.atmosphere;
  if (id === 800) return WEATHER_SEVERITY.clear;
  if (id > 800 && id < 900) return WEATHER_SEVERITY.clouds;

  return WEATHER_SEVERITY.unknown;
}

export async function fetchWeather(
  latitude: number | null,
  longitude: number | null,
): Promise<WeatherContext> {
  const key = Deno.env.get("OPENWEATHER_API_KEY");

  if (!key) {
    console.warn(
      "OPENWEATHER_API_KEY is not set; weather factor will be skipped",
    );
    return UNAVAILABLE;
  }
  if (latitude === null || longitude === null) {
    return UNAVAILABLE;
  }

  const url = `https://api.openweathermap.org/data/2.5/weather` +
    `?lat=${latitude}&lon=${longitude}&units=metric&appid=${key}`;

  try {
    const response = await fetch(url, {
      signal: AbortSignal.timeout(EXTERNAL_API_TIMEOUT_MS),
    });

    if (!response.ok) {
      // 401 in the first two hours after signup is normal: the key is still
      // activating. Worth logging clearly so it is not mistaken for a bug.
      console.warn(
        `OpenWeatherMap returned ${response.status}` +
          (response.status === 401 ? " (new keys take ~2h to activate)" : ""),
      );
      return UNAVAILABLE;
    }

    const body = (await response.json()) as WeatherResponse;
    const entry = body.weather?.[0];

    if (!entry) return UNAVAILABLE;

    const severity = severityForConditionId(entry.id);
    const description = entry.description ?? entry.main ?? "current conditions";

    return {
      available: true,
      condition: entry.main ?? null,
      description,
      tempC: typeof body.main?.temp === "number" ? body.main.temp : null,
      severity,
      label: severity === 0 ? "clear weather" : description,
    };
  } catch (error) {
    console.warn("OpenWeatherMap request failed", (error as Error).message);
    return UNAVAILABLE;
  }
}
