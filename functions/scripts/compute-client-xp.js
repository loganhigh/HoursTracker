#!/usr/bin/env node
/**
 * Replicates the iOS client's GamificationEngine XP math from Firestore
 * timeEntries + paySettings, so an admin offset can be calibrated against the
 * XP the DEVICE actually computes (hourly + logging + overtime + streak +
 * long-shift + weekly-completion XP) instead of a stale synced totalXP.
 *
 * Read-only. Usage (from functions/):
 *   node scripts/compute-client-xp.js <uid> [targetLevel] [targetPrestige]
 */

const fs = require("fs");
const os = require("os");

const PROJECT_ID = "hour-tracker-1fa55";
const CLIENT_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi";
const TZ = "America/Denver"; // device-local calendar for day/week bucketing

// GamificationEngine constants (HoursStore.swift)
const XP_PER_HOUR = 100;
const SHIFT_LOG_XP = 50;
const OVERTIME_XP_PER_HOUR = 150;
const STREAK_DAY_XP = 200;
const LONG_SHIFT_XP = 300;
const WEEKLY_COMPLETION_XP = 500;
const MAX_LEVEL = 25;

function xpRequiredForLevel(level) {
  const l = Math.max(1, level);
  return Math.floor(900 + (l - 1) * 180 + Math.pow(l - 1, 1.22) * 18);
}
function totalXPForFullPrestigeRun() {
  let t = 0;
  for (let l = 1; l <= MAX_LEVEL; l++) t += xpRequiredForLevel(l);
  return t;
}
function xpIntoRunAtLevelStart(level) {
  let t = 0;
  for (let l = 1; l < level; l++) t += xpRequiredForLevel(l);
  return t;
}

async function getAccessToken() {
  const cfg = JSON.parse(fs.readFileSync(os.homedir() + "/.config/configstore/firebase-tools.json", "utf8"));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: cfg.tokens.refresh_token,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
    }),
  });
  if (!res.ok) throw new Error("token exchange failed: " + (await res.text()));
  return (await res.json()).access_token;
}

function flat(v) {
  if (v == null) return null;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("stringValue" in v) return v.stringValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("timestampValue" in v) return new Date(v.timestampValue);
  if ("nullValue" in v) return null;
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(flat);
  if ("mapValue" in v) {
    const out = {};
    for (const [k, mv] of Object.entries(v.mapValue.fields || {})) out[k] = flat(mv);
    return out;
  }
  return v;
}

async function getJSON(token, url) {
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`GET -> ${res.status}: ${await res.text()}`);
  return res.json();
}

async function loadCollection(token, path) {
  const base = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`;
  const docs = [];
  let pageToken = "";
  do {
    const url = base + `?pageSize=300${pageToken ? `&pageToken=${pageToken}` : ""}`;
    const json = await getJSON(token, url);
    for (const d of json?.documents || []) {
      const out = {};
      for (const [k, v] of Object.entries(d.fields || {})) out[k] = flat(v);
      docs.push(out);
    }
    pageToken = json?.nextPageToken || "";
  } while (pageToken);
  return docs;
}

// Matches WorkEntry.paidHours / server paidHours().
function paidHours(e) {
  if (e.isOffDay) return 0;
  if (!(e.start instanceof Date) || !(e.end instanceof Date)) return 0;
  let raw = (e.end - e.start) / 3600000;
  if (raw < 0) raw += 24;
  const brk = Math.max(0, Number(e.breakMinutes) || 0) / 60;
  return Math.max(0, raw - brk);
}

const dayFmt = new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" });
const weekdayFmt = new Intl.DateTimeFormat("en-US", { timeZone: TZ, weekday: "short" });

function localDayKey(date) {
  return dayFmt.format(date); // YYYY-MM-DD in device TZ
}
function weekdayIndex(date) {
  // Swift Calendar: 1=Sun ... 7=Sat
  return { Sun: 1, Mon: 2, Tue: 3, Wed: 4, Thu: 5, Fri: 6, Sat: 7 }[weekdayFmt.format(date)];
}
function mondayWeekKey(date) {
  const key = localDayKey(date);
  const [y, m, d] = key.split("-").map(Number);
  const noonUTC = new Date(Date.UTC(y, m - 1, d, 12)); // DST-safe day arithmetic
  const wd = noonUTC.getUTCDay(); // 0=Sun
  const diffToMonday = wd === 0 ? -6 : 1 - wd;
  noonUTC.setUTCDate(noonUTC.getUTCDate() + diffToMonday);
  return noonUTC.toISOString().slice(0, 10);
}

// Per-entry overtime hours, mirroring HoursStore.payBreakdown().
function overtimeHoursFor(entry, weekEntriesSorted, s) {
  const raw = paidHours(entry);
  const wd = weekdayIndex(entry.date);
  const satThreshold = Number(s.saturdayOvertimeAfterHours) || 8;
  const wdAfter = Number(s.weekdayOvertimeAfterHours) || 8;
  const weeklyCap = Number(s.weeklyOvertimeThreshold) || 40;
  const type = s.overtimeType || "daily";

  if (wd === 7) return Math.max(0, raw - satThreshold); // Saturday past threshold
  if (wd === 1) return raw; // Sunday: ALL hours at 2.0x count as OT

  if (type === "weekly") {
    let remaining = weeklyCap;
    let result = 0;
    for (const e of weekEntriesSorted) {
      const h = paidHours(e);
      const reg = Math.min(h, Math.max(0, remaining));
      remaining -= reg;
      if (e.__id === entry.__id) result = h - reg;
    }
    return result;
  }
  if (type === "dailyAndWeekly") {
    const dailyReg = Math.min(raw, wdAfter);
    const dailyOT = raw - dailyReg;
    let weeklyRemaining = weeklyCap;
    let weeklyOT = 0;
    for (const e of weekEntriesSorted) {
      const r = Math.max(0, paidHours(e));
      const dReg = Math.min(r, wdAfter);
      const wReg = Math.min(dReg, Math.max(0, weeklyRemaining));
      weeklyRemaining -= wReg;
      if (e.__id === entry.__id) weeklyOT = dReg - wReg;
    }
    return dailyOT + weeklyOT;
  }
  // daily (default)
  return Math.max(0, raw - wdAfter);
}

async function main() {
  const [uid, levelArg, prestigeArg] = process.argv.slice(2);
  if (!uid) {
    console.error("usage: node scripts/compute-client-xp.js <uid> [targetLevel] [targetPrestige]");
    process.exit(1);
  }
  const token = await getAccessToken();

  const [entriesRaw, settingsDocs] = await Promise.all([
    loadCollection(token, `users/${uid}/timeEntries`),
    getJSON(
      token,
      `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}/paySettings/current`
    ),
  ]);
  const s = {};
  for (const [k, v] of Object.entries(settingsDocs?.fields || {})) s[k] = flat(v);

  // Client writes date/start/end as epoch milliseconds (integerValue).
  const toDate = (v) => (v instanceof Date ? v : typeof v === "number" && v > 0 ? new Date(v) : null);
  let idc = 0;
  const entries = entriesRaw
    .map((e) => ({ ...e, __id: idc++, date: toDate(e.date), start: toDate(e.start), end: toDate(e.end) }))
    .filter((e) => e.date instanceof Date);
  const work = entries.filter((e) => !e.isOffDay && paidHours(e) > 0);

  // Group by Monday-start week for weekly OT + weekly-completion XP.
  const byWeek = new Map();
  for (const e of work) {
    const wk = mondayWeekKey(e.date);
    if (!byWeek.has(wk)) byWeek.set(wk, []);
    byWeek.get(wk).push(e);
  }
  for (const arr of byWeek.values()) arr.sort((a, b) => a.date - b.date);

  const totalHours = work.reduce((t, e) => t + paidHours(e), 0);
  const hourlyXP = Math.round(totalHours * XP_PER_HOUR);
  const loggingXP = work.length * SHIFT_LOG_XP;

  let overtimeHoursTotal = 0;
  for (const e of work) {
    overtimeHoursTotal += overtimeHoursFor(e, byWeek.get(mondayWeekKey(e.date)), s);
  }
  const overtimeXP = Math.round(overtimeHoursTotal * OVERTIME_XP_PER_HOUR);

  const workedDays = new Set(work.map((e) => localDayKey(e.date)));
  const streakXP = workedDays.size * STREAK_DAY_XP;

  const longShiftXP = work.filter((e) => paidHours(e) >= 12).length * LONG_SHIFT_XP;

  let completedWeeks = 0;
  for (const arr of byWeek.values()) {
    const wkHours = arr.reduce((t, e) => t + paidHours(e), 0);
    if (wkHours >= 40) completedWeeks += 1;
  }
  const weeklyXP = completedWeeks * WEEKLY_COMPLETION_XP;

  const E = hourlyXP + loggingXP + overtimeXP + streakXP + longShiftXP + weeklyXP;

  console.log({
    overtimeType: s.overtimeType || "daily",
    weekdayOTAfter: s.weekdayOvertimeAfterHours,
    entries: work.length,
    totalHours: totalHours.toFixed(2),
    overtimeHoursTotal: overtimeHoursTotal.toFixed(2),
    hourlyXP, loggingXP, overtimeXP, streakXP, longShiftXP,
    completedWeeks, weeklyXP,
    clientEntryXP: E,
  });

  if (levelArg) {
    const targetLevel = Number(levelArg);
    const targetPrestige = Number(prestigeArg ?? 0);
    const run = totalXPForFullPrestigeRun();
    const targetTotal = targetPrestige * run + xpIntoRunAtLevelStart(targetLevel);
    console.log({
      targetLevel, targetPrestige,
      requiredTotalXPAtLevelStart: targetTotal,
      proposedAdminXPOffset: targetTotal - E,
      note: "device totalXP = clientEntryXP + challengeXP + offset; challenges only push slightly past level start",
    });
  }
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
