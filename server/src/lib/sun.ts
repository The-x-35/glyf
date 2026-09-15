/** Sunrise and sunset, computed — not fetched.
 *
 *  "What time does the sun set" is the answer card on the site, so it has to
 *  be right and instant. It is also pure astronomy: given a date and a
 *  coordinate the answer is deterministic, so there is no reason to pay an
 *  API, wait on a network round trip, or inherit someone's licence terms.
 *
 *  Implements the standard sunrise equation (NOAA / Wikipedia formulation).
 *  Accurate to well under a minute, which is far finer than anyone reads off
 *  a keyboard card.
 */

const rad = Math.PI / 180;
const J2000 = 2451545.0;
/** Earth's axial tilt. */
const OBLIQUITY = 23.4397;
/** Standard refraction-corrected solar altitude at sunrise/sunset. */
const ZENITH = -0.833;

function toJulian(date: Date): number {
  return date.getTime() / 86400000 + 2440587.5;
}

function fromJulian(j: number): Date {
  return new Date((j - 2440587.5) * 86400000);
}

export interface SunTimes {
  sunrise: Date | null;
  sunset: Date | null;
  /** Civil dawn/dusk — "golden hour begins" on the site's second card. */
  goldenHour: Date | null;
  /** True inside the polar day/night, where no rise or set happens. */
  polar: "day" | "night" | null;
}

/**
 * @param lat  degrees, north positive
 * @param lon  degrees, EAST positive
 */
export function sunTimes(lat: number, lon: number, date = new Date()): SunTimes {
  // Days since J2000, shifted so the "day" is centred on local solar noon.
  const n = Math.round(toJulian(date) - J2000 - 0.0009 + lon / 360);
  const meanSolarNoon = n + 0.0009 - lon / 360;

  // Solar mean anomaly.
  const M = (357.5291 + 0.98560028 * meanSolarNoon) % 360;
  // Equation of the centre.
  const C = 1.9148 * Math.sin(M * rad)
    + 0.02 * Math.sin(2 * M * rad)
    + 0.0003 * Math.sin(3 * M * rad);
  // Ecliptic longitude.
  const lambda = (M + C + 180 + 102.9372) % 360;
  // Solar transit (local noon) as a Julian date.
  const transit = J2000 + meanSolarNoon
    + 0.0053 * Math.sin(M * rad)
    - 0.0069 * Math.sin(2 * lambda * rad);

  const declination = Math.asin(Math.sin(lambda * rad) * Math.sin(OBLIQUITY * rad));

  const hourAngle = (altitude: number): number | null => {
    const cosOmega = (Math.sin(altitude * rad) - Math.sin(lat * rad) * Math.sin(declination))
      / (Math.cos(lat * rad) * Math.cos(declination));
    // Outside ±1 the sun never reaches that altitude on this date.
    if (cosOmega > 1 || cosOmega < -1) return null;
    return Math.acos(cosOmega) / rad;
  };

  const omega = hourAngle(ZENITH);
  if (omega === null) {
    // Which side of the pole we are on decides day vs night.
    const midday = Math.sin(lat * rad) * Math.sin(declination)
      + Math.cos(lat * rad) * Math.cos(declination);
    return {
      sunrise: null, sunset: null, goldenHour: null,
      polar: midday > Math.sin(ZENITH * rad) ? "day" : "night",
    };
  }

  // 6° above the horizon is the usual "golden hour begins" threshold.
  const omegaGolden = hourAngle(6);

  return {
    sunrise: fromJulian(transit - omega / 360),
    sunset: fromJulian(transit + omega / 360),
    goldenHour: omegaGolden === null ? null : fromJulian(transit + omegaGolden / 360),
    polar: null,
  };
}

/** 6:13 PM, in the caller's zone. */
export function clockIn(date: Date, tz?: string): string {
  try {
    return new Intl.DateTimeFormat("en-US", {
      hour: "numeric", minute: "2-digit", hour12: true,
      ...(tz ? { timeZone: tz } : {}),
    }).format(date);
  } catch {
    return new Intl.DateTimeFormat("en-US", {
      hour: "numeric", minute: "2-digit", hour12: true,
    }).format(date);
  }
}
