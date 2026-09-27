/**
 * Per-user calendar math. Cloud Functions run in UTC while users live in
 * their own timezones, and every day-boundary decision in stats (cheque
 * windows, weekly totals, streaks, "today") has to follow the USER's
 * calendar — the observed failure was the server rolling cheque windows six
 * hours early for Mountain-time users every cutoff evening.
 *
 * A calendar is built from an IANA zone via Intl (DST-correct), and the zone
 * is resolved per user:
 *   1. `users/{uid}.timeZone` — the app publishes TimeZone.current.identifier
 *      with every profile snapshot (builds after 3.0 (32)).
 *   2. Derived from the user's own data: every WorkEntry `date` (and the saved
 *      cutoff/payday) is LOCAL MIDNIGHT as an instant, so its UTC time-of-day
 *      is exactly the user's offset. The latest entry reflects current DST.
 *      Whole-hour offsets map to fixed "Etc/GMT±N" zones (sign inverted by
 *      convention: Etc/GMT+6 is UTC-6); the few half-hour zones map to a
 *      representative named zone.
 *   3. America/Edmonton — where the user base started.
 */

const MS_DAY = 86400000;
const DEFAULT_TIME_ZONE = "America/Edmonton";
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function isValidTimeZone(tz) {
  if (typeof tz !== "string" || !tz.trim()) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

const pad2 = (n) => String(n).padStart(2, "0");

function makeCalendar(tz = DEFAULT_TIME_ZONE) {
  const zone = isValidTimeZone(tz) ? tz : DEFAULT_TIME_ZONE;
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: zone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    weekday: "short",
  });

  /** Local wall-clock fields of an instant. */
  function parts(date) {
    const o = {};
    for (const p of fmt.formatToParts(date)) o[p.type] = p.value;
    return {
      y: Number(o.year),
      m: Number(o.month),
      d: Number(o.day),
      h: Number(o.hour) % 24,
      min: Number(o.minute),
      s: Number(o.second),
      weekday: WEEKDAYS.indexOf(o.weekday),
    };
  }

  /** Zone offset (local − UTC, ms) in effect at `date`. */
  function offsetAt(date) {
    const p = parts(date);
    const wall = Date.UTC(p.y, p.m - 1, p.d, p.h, p.min, p.s);
    return wall - Math.floor(date.getTime() / 1000) * 1000;
  }

  /** The instant of local midnight on local calendar day y/m/d (d may overflow). */
  function localMidnight(y, m, d) {
    const wall = Date.UTC(y, m - 1, d);
    let t = wall - offsetAt(new Date(wall));
    const off = offsetAt(new Date(t));
    if (wall - off !== t) t = wall - off; // DST transition between guesses
    return new Date(t);
  }

  const startOfDay = (date) => {
    const p = parts(date);
    return localMidnight(p.y, p.m, p.d);
  };

  return {
    timeZone: zone,
    startOfDay,
    /** Local midnight `n` days after the local day containing `date`. */
    addDays(date, n) {
      const p = parts(date);
      return localMidnight(p.y, p.m, p.d + n);
    },
    /** "yyyy-MM-dd" of the local day containing `date`. */
    isoDate(date) {
      const p = parts(date);
      return `${p.y}-${pad2(p.m)}-${pad2(p.d)}`;
    },
    /** Local midnight for a "yyyy-MM-dd" string. */
    fromISO(iso) {
      const [y, m, d] = String(iso).split("-").map(Number);
      return localMidnight(y, m, d);
    },
    /** 0 Sunday … 6 Saturday, local. */
    weekday(date) {
      return parts(date).weekday;
    },
    monthStart(date) {
      const p = parts(date);
      return localMidnight(p.y, p.m, 1);
    },
    yearStart(date) {
      const p = parts(date);
      return localMidnight(p.y, 1, 1);
    },
    /** Whole local calendar days from `b` to `a` (positive when `a` is later). */
    dayDiff(a, b) {
      const pa = parts(a);
      const pb = parts(b);
      return Math.round(
        (Date.UTC(pa.y, pa.m - 1, pa.d) - Date.UTC(pb.y, pb.m - 1, pb.d)) / MS_DAY
      );
    },
  };
}

function toMs(value) {
  if (value == null) return null;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "object" && typeof value._seconds === "number") {
    return value._seconds * 1000 + Math.floor((value._nanoseconds || 0) / 1e6);
  }
  return null;
}

/**
 * Offset (minutes, local − UTC) implied by an instant that is a LOCAL
 * MIDNIGHT. null when the instant isn't on a 15-minute boundary (not a
 * midnight at all) or the implied offset is outside ±14h.
 */
function offsetMinutesFromLocalMidnight(ms) {
  if (ms == null || !Number.isFinite(ms)) return null;
  const rem = ((ms % MS_DAY) + MS_DAY) % MS_DAY; // UTC time-of-day at local midnight
  if (rem % (15 * 60000) !== 0) return null;
  let offMin = -(rem / 60000);
  if (offMin < -12 * 60) offMin += 24 * 60;
  if (offMin < -14 * 60 || offMin > 14 * 60) return null;
  return offMin;
}

const HALF_HOUR_ZONES = {
  "-210": "America/St_Johns", // NST
  "-150": "America/St_Johns", // NDT
  "330": "Asia/Kolkata",
  "345": "Asia/Kathmandu",
  "570": "Australia/Adelaide",
  "630": "Australia/Adelaide", // ACDT
  "-270": "America/Caracas",
  "270": "Asia/Kabul",
  "210": "Asia/Tehran",
  "390": "Asia/Yangon",
};

/** Fixed-offset (or representative) IANA zone for an offset in minutes. */
function timeZoneForOffsetMinutes(offMin) {
  if (offMin == null) return null;
  if (offMin === 0) return "Etc/UTC";
  if (offMin % 60 === 0) {
    const h = offMin / 60;
    // Etc/GMT sign is inverted: Etc/GMT+6 means UTC−6.
    return `Etc/GMT${h > 0 ? "-" : "+"}${Math.abs(h)}`;
  }
  return HALF_HOUR_ZONES[String(offMin)] || null;
}

/**
 * @param {{ userData?: object, paySettings?: object, entries?: object[] }} input
 * @returns {{ timeZone: string, source: "profile"|"entries"|"paySettings"|"default" }}
 */
function resolveUserTimeZone({ userData, paySettings, entries } = {}) {
  const explicit = String(userData?.timeZone || "").trim();
  if (explicit && isValidTimeZone(explicit)) {
    return { timeZone: explicit, source: "profile" };
  }

  let latest = null;
  for (const e of entries || []) {
    const ms = toMs(e?.date);
    if (ms != null && (latest == null || ms > latest)) latest = ms;
  }
  const fromEntries = timeZoneForOffsetMinutes(offsetMinutesFromLocalMidnight(latest));
  if (fromEntries) return { timeZone: fromEntries, source: "entries" };

  for (const key of ["nextCutoff", "nextPayday"]) {
    const tz = timeZoneForOffsetMinutes(offsetMinutesFromLocalMidnight(toMs(paySettings?.[key])));
    if (tz) return { timeZone: tz, source: "paySettings" };
  }

  return { timeZone: DEFAULT_TIME_ZONE, source: "default" };
}

module.exports = {
  DEFAULT_TIME_ZONE,
  MS_DAY,
  isValidTimeZone,
  makeCalendar,
  offsetMinutesFromLocalMidnight,
  timeZoneForOffsetMinutes,
  resolveUserTimeZone,
};
