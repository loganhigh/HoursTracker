/**
 * Server-side stats recompute for timeEntries writes.
 * Maintains users/{uid}/stats/*, publicProfiles/*, legacy users/{uid} mirror,
 * and server-written activity events.
 */

const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const MS_DAY = 86400000;

function paidHours(entry) {
  if (entry.isOffDay) return 0;
  const startMs = toMs(entry.start);
  const endMs = toMs(entry.end);
  if (startMs == null || endMs == null) return 0;
  let raw = (endMs - startMs) / 3600000;
  if (raw < 0) raw += 24;
  const breakHrs = Math.max(0, Number(entry.breakMinutes) || 0) / 60;
  return Math.max(0, raw - breakHrs);
}

function toMs(value) {
  if (value == null) return null;
  if (value instanceof Timestamp) return value.toMillis();
  if (typeof value === "number") return value;
  if (typeof value === "object" && typeof value._seconds === "number") {
    return value._seconds * 1000 + Math.floor((value._nanoseconds || 0) / 1e6);
  }
  return null;
}

function entryDate(entry) {
  const ms = toMs(entry.date);
  return ms == null ? null : new Date(ms);
}

function startOfDay(date, calendarOffset = 0) {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  return d;
}

/** Monday-aligned week interval containing `now`. */
function currentWeekInterval(now = new Date()) {
  const d = startOfDay(now);
  const day = d.getDay(); // 0 Sun .. 6 Sat
  const diffToMonday = day === 0 ? -6 : 1 - day;
  const start = new Date(d.getTime() + diffToMonday * MS_DAY);
  const end = new Date(start.getTime() + 7 * MS_DAY);
  return { start, end };
}

function inInterval(date, interval) {
  const t = date.getTime();
  return t >= interval.start.getTime() && t < interval.end.getTime();
}

function weeklyStats(entries, now = new Date()) {
  const interval = currentWeekInterval(now);
  let hours = 0;
  let shifts = 0;
  const days = new Set();
  for (const entry of entries) {
    const date = entryDate(entry);
    if (!date || entry.isOffDay || !inInterval(date, interval)) continue;
    hours += paidHours(entry);
    shifts += 1;
    days.add(startOfDay(date).toISOString().slice(0, 10));
  }
  return {
    weekStart: interval.start,
    weekEnd: interval.end,
    hours,
    shifts,
    daysWorked: days.size,
  };
}

function spanDays(payPeriodType) {
  return payPeriodType === "weekly" ? 7 : 14;
}

function normalizedPaydayBoundary(settings) {
  if (settings.nextPayday != null) {
    return startOfDay(new Date(toMs(settings.nextPayday)));
  }
  const span = spanDays(settings.payPeriodType || "biWeekly");
  const now = startOfDay(new Date());
  return new Date(now.getTime() + span * MS_DAY);
}

function usesSavedCutoff(settings) {
  return settings.payPeriodUsesCutoff === true && settings.nextCutoff != null;
}

function makeCycleFromCutoff(cutoff, settings) {
  const span = spanDays(settings.payPeriodType || "biWeekly");
  const cutoffDay = startOfDay(new Date(toMs(cutoff)));
  const end = new Date(cutoffDay.getTime() + MS_DAY);
  const start = new Date(end.getTime() - span * MS_DAY);
  return { start, end, cutoff: cutoffDay };
}

function makeCycle(payday, settings) {
  const span = spanDays(settings.payPeriodType || "biWeekly");
  const paydayStart = startOfDay(payday);
  const end = paydayStart;
  const start = new Date(end.getTime() - span * MS_DAY);
  const cutoff = new Date(end.getTime() - MS_DAY);
  return { start, end, cutoff };
}

function currentPayCycle(settings, asOf = new Date()) {
  const d = startOfDay(asOf);
  const span = spanDays(settings.payPeriodType || "biWeekly");

  if (usesSavedCutoff(settings)) {
    let cutoff = startOfDay(new Date(toMs(settings.nextCutoff)));
    let cycle = makeCycleFromCutoff(cutoff, settings);
    while (d < cycle.start) {
      cutoff = new Date(cutoff.getTime() - span * MS_DAY);
      cycle = makeCycleFromCutoff(cutoff, settings);
    }
    while (d >= cycle.end) {
      cutoff = new Date(cutoff.getTime() + span * MS_DAY);
      cycle = makeCycleFromCutoff(cutoff, settings);
    }
    return cycle;
  }

  let payday = normalizedPaydayBoundary(settings);
  let cycle = makeCycle(payday, settings);
  while (d < cycle.start) {
    payday = new Date(payday.getTime() - span * MS_DAY);
    cycle = makeCycle(payday, settings);
  }
  while (d >= cycle.end) {
    payday = new Date(payday.getTime() + span * MS_DAY);
    cycle = makeCycle(payday, settings);
  }
  return cycle;
}

function payPeriodStats(entries, settings, now = new Date()) {
  const cycle = currentPayCycle(settings, now);
  let hours = 0;
  let shifts = 0;
  const days = new Set();
  for (const entry of entries) {
    const date = entryDate(entry);
    if (!date || entry.isOffDay) continue;
    const t = date.getTime();
    if (t < cycle.start.getTime() || t >= cycle.end.getTime()) continue;
    hours += paidHours(entry);
    shifts += 1;
    days.add(startOfDay(date).toISOString().slice(0, 10));
  }
  return {
    periodStart: cycle.start,
    periodEnd: cycle.end,
    hours,
    shifts,
    daysWorked: days.size,
  };
}

function totalPaidHours(entries) {
  return entries.reduce((sum, e) => sum + (e.isOffDay ? 0 : paidHours(e)), 0);
}

function workedDays(entries) {
  const days = new Set();
  for (const entry of entries) {
    if (entry.isOffDay) continue;
    const date = entryDate(entry);
    if (!date) continue;
    days.add(startOfDay(date).toISOString().slice(0, 10));
  }
  return [...days].sort().map((s) => new Date(s + "T00:00:00"));
}

function currentStreak(workedDayStrings) {
  if (workedDayStrings.length === 0) return 0;
  const today = startOfDay(new Date()).toISOString().slice(0, 10);
  const yesterday = new Date(startOfDay(new Date()).getTime() - MS_DAY)
    .toISOString()
    .slice(0, 10);
  const set = new Set(workedDayStrings);
  let anchor = set.has(today) ? today : set.has(yesterday) ? yesterday : null;
  if (!anchor) return 0;
  let streak = 0;
  let cursor = new Date(anchor + "T00:00:00");
  while (set.has(cursor.toISOString().slice(0, 10))) {
    streak += 1;
    cursor = new Date(cursor.getTime() - MS_DAY);
  }
  return streak;
}

function bestStreak(workedDayStrings) {
  if (workedDayStrings.length === 0) return 0;
  const sorted = [...workedDayStrings].sort();
  let best = 1;
  let run = 1;
  for (let i = 1; i < sorted.length; i++) {
    const prev = new Date(sorted[i - 1] + "T00:00:00").getTime();
    const cur = new Date(sorted[i] + "T00:00:00").getTime();
    if (cur - prev === MS_DAY) {
      run += 1;
      best = Math.max(best, run);
    } else if (sorted[i] !== sorted[i - 1]) {
      run = 1;
    }
  }
  return best;
}

function levelFromXP(totalXP, prestige = 0) {
  let xp = Math.max(0, Number(totalXP) || 0);
  let level = 1;
  const maxLevel = prestige > 0 ? 50 + prestige * 10 : 50;
  while (level < maxLevel) {
    const req = xpRequiredForLevel(level);
    if (xp < req) break;
    xp -= req;
    level += 1;
  }
  return Math.min(level, maxLevel);
}

function xpRequiredForLevel(level) {
  const l = Math.max(1, level);
  return Math.floor(100 + (l - 1) * 25 + Math.pow(l - 1, 1.35) * 15);
}

function privacyFlags(userData) {
  const privacy = userData?.privacy || {};
  return {
    shareHours: privacy.shareHours !== false,
    shareBadges: privacy.shareBadges !== false,
    shareActivity: privacy.shareActivity !== false,
  };
}

function isoDate(d) {
  return d.toISOString().slice(0, 10);
}

async function loadPaySettings(db, uid) {
  const snap = await db
    .collection("users")
    .doc(uid)
    .collection("paySettings")
    .doc("current")
    .get();
  return snap.exists ? snap.data() : { payPeriodType: "biWeekly" };
}

async function loadGamification(db, uid) {
  const snap = await db
    .collection("users")
    .doc(uid)
    .collection("gamification")
    .doc("current")
    .get();
  return snap.exists ? snap.data() : {};
}

async function loadAllTimeEntries(db, uid) {
  const snap = await db.collection("users").doc(uid).collection("timeEntries").get();
  if (!snap.empty) {
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  }
  const legacy = await db.collection("users").doc(uid).collection("entries").get();
  return legacy.docs.map((d) => ({ id: d.id, ...d.data() }));
}

async function emitShiftActivityIfNeeded(db, uid, userData, beforeEntry, afterEntry) {
  if (!afterEntry || afterEntry.isOffDay) return;
  const hours = paidHours(afterEntry);
  if (hours <= 0) return;
  const privacy = privacyFlags(userData);
  if (!privacy.shareActivity) return;

  const date = entryDate(afterEntry);
  if (!date) return;
  const now = new Date();
  const dayDiff = Math.floor(
    (startOfDay(now).getTime() - startOfDay(date).getTime()) / MS_DAY
  );
  if (dayDiff > 1) return;

  const isNew = !beforeEntry && afterEntry;
  const materiallyChanged =
    beforeEntry &&
    afterEntry &&
    (paidHours(beforeEntry) !== hours ||
      toMs(beforeEntry.date) !== toMs(afterEntry.date) ||
      beforeEntry.isOffDay !== afterEntry.isOffDay);
  if (!isNew && !materiallyChanged) return;

  const hoursStr = hours.toFixed(2);
  let body;
  if (dayDiff === 0) body = `worked ${hoursStr} today`;
  else if (dayDiff === 1) body = `worked ${hoursStr} yesterday`;
  else body = `logged a ${hoursStr} shift`;

  const eventId = `shift_${afterEntry.id || "unknown"}`;
  const ref = db.collection("users").doc(uid).collection("activity").doc(eventId);
  const existing = await ref.get();
  if (existing.exists && !materiallyChanged) return;

  await ref.set(
    {
      kind: "shiftLogged",
      body,
      metric: hours,
      createdAt: FieldValue.serverTimestamp(),
      source: "server",
    },
    { merge: true }
  );
}

/**
 * Recompute all stats for a user and write summary docs.
 * @param {import('firebase-admin/firestore').Firestore} db
 * @param {string} uid
 * @param {{ beforeEntry?: object, afterEntry?: object }} [options]
 */
async function recomputeUserStats(db, uid, options = {}) {
  const [entries, paySettings, gamification, userSnap] = await Promise.all([
    loadAllTimeEntries(db, uid),
    loadPaySettings(db, uid),
    loadGamification(db, uid),
    db.collection("users").doc(uid).get(),
  ]);

  const userData = userSnap.exists ? userSnap.data() : {};
  const now = new Date();
  const week = weeklyStats(entries, now);
  const payPeriod = payPeriodStats(entries, paySettings, now);
  const worked = workedDays(entries);
  const workedStrings = worked.map((d) => isoDate(d));
  const streak = currentStreak(workedStrings);
  const best = bestStreak(workedStrings);
  const totalHours = totalPaidHours(entries);

  const totalXP =
    Number(gamification.totalXP) ||
    Number(userData.totalXP) ||
    0;
  const prestige =
    Number(gamification.prestige) ||
    Number(userData.prestige) ||
    0;
  const adminLevel = userData.adminLevel != null ? Number(userData.adminLevel) : null;
  const xpLevel = levelFromXP(totalXP, prestige);
  const level = Math.max(adminLevel || 0, xpLevel);
  const badgeCount =
    Number(userData.badgeCount) ||
    (Array.isArray(gamification.unlockedBadges) ? gamification.unlockedBadges.length : 0);

  const privacy = privacyFlags(userData);
  const batch = db.batch();
  const updatedAt = FieldValue.serverTimestamp();

  const weekRef = db.collection("users").doc(uid).collection("stats").doc("currentWeek");
  batch.set(weekRef, {
    weekStart: Timestamp.fromDate(week.weekStart),
    weekEnd: Timestamp.fromDate(week.weekEnd),
    hours: week.hours,
    shifts: week.shifts,
    daysWorked: week.daysWorked,
    currentStreak: streak,
    updatedAt,
  });

  const payRef = db.collection("users").doc(uid).collection("stats").doc("currentPayPeriod");
  batch.set(payRef, {
    periodStart: Timestamp.fromDate(payPeriod.periodStart),
    periodEnd: Timestamp.fromDate(payPeriod.periodEnd),
    hours: payPeriod.hours,
    shifts: payPeriod.shifts,
    daysWorked: payPeriod.daysWorked,
    updatedAt,
  });

  const lifetimeRef = db.collection("users").doc(uid).collection("stats").doc("lifetime");
  batch.set(lifetimeRef, {
    totalHours,
    totalXP,
    level,
    prestige,
    bestStreak: best,
    badgeCount,
    updatedAt,
  });

  const publicProfile = {
    displayName: userData.displayName || "Friend",
    friendCode: userData.friendCode || null,
    level,
    prestige,
    totalHours: privacy.shareHours ? totalHours : 0,
    chequeHours: privacy.shareHours ? payPeriod.hours : 0,
    bestStreak: privacy.shareHours ? best : 0,
    currentStreak: privacy.shareHours ? streak : 0,
    equippedTitle: userData.adminEquippedTitle || userData.equippedTitle || "",
    profilePhotoURL: userData.profilePhotoURL || null,
    privacy: userData.privacy || {},
    acceptInvites: userData.acceptInvites !== false,
    companyName: userData.companyName || "",
    companyHoursLogged: privacy.shareHours ? companyHoursLogged : 0,
    companyDaysWorked: privacy.shareHours ? companyDaysWorked : 0,
    badgeCount,
    updatedAt,
  };
  batch.set(db.collection("publicProfiles").doc(uid), publicProfile, { merge: true });

  const publicWeek = {
    hours: privacy.shareHours ? week.hours : 0,
    shifts: privacy.shareHours ? week.shifts : 0,
    daysWorked: privacy.shareHours ? week.daysWorked : 0,
    currentStreak: privacy.shareHours ? streak : 0,
    weekStart: Timestamp.fromDate(week.weekStart),
    updatedAt,
  };
  batch.set(
    db.collection("publicProfiles").doc(uid).collection("stats").doc("currentWeek"),
    publicWeek,
    { merge: true }
  );

  // Company stats — hours and days since companyStartDate
  const companyStart = userData.companyStartDate?.toDate?.() || null;
  const workEntries = entries.filter((e) => !e.isOffDay);
  const companyEntries = companyStart
    ? workEntries.filter((e) => {
        const d = entryDate(e);
        return d && d >= startOfDay(companyStart);
      })
    : workEntries;
  const companyHoursLogged = companyEntries.reduce((s, e) => s + paidHours(e), 0);
  const companyDaysWorked = new Set(
    companyEntries.map((e) => isoDate(entryDate(e))).filter(Boolean)
  ).size;

  // Per-day breakdown for the current pay cheque
  const chequeDailySummary = (() => {
    if (!privacy.shareHours) return [];
    const today = startOfDay(now);
    const cutoff = payPeriod.periodEnd < today ? payPeriod.periodEnd : today;
    const grouped = {};
    for (const entry of entries) {
      const d = entryDate(entry);
      if (!d || entry.isOffDay) continue;
      const t = d.getTime();
      if (t < payPeriod.periodStart.getTime() || t >= payPeriod.periodEnd.getTime()) continue;
      const key = isoDate(d);
      if (!grouped[key]) grouped[key] = { hours: 0, shifts: 0 };
      grouped[key].hours += paidHours(entry);
      grouped[key].shifts += 1;
    }
    const result = [];
    const cursor = new Date(payPeriod.periodStart);
    while (cursor <= cutoff) {
      const key = isoDate(cursor);
      const day = grouped[key] || { hours: 0, shifts: 0 };
      result.push({ date: key, hours: day.hours, shifts: day.shifts });
      cursor.setDate(cursor.getDate() + 1);
    }
    return result;
  })();

  const legacyMirror = {
    weeklyHours: privacy.shareHours ? week.hours : 0,
    weeklyShiftsLogged: privacy.shareHours ? week.shifts : 0,
    weeklyDaysLogged: privacy.shareHours ? week.daysWorked : 0,
    currentStreak: streak,
    bestStreak: best,
    totalHours,
    chequeHours: payPeriod.hours,
    level,
    prestige,
    totalXP,
    badgeCount,
    updatedAt,
  };
  if (privacy.shareHours) {
    legacyMirror.companyHoursLogged = companyHoursLogged;
    legacyMirror.companyDaysWorked = companyDaysWorked;
    legacyMirror.chequeDailySummary = chequeDailySummary;
    legacyMirror.chequeWindowStart = isoDate(payPeriod.periodStart);
    legacyMirror.chequeWindowCutoff = isoDate(payPeriod.periodEnd);
  }
  batch.set(db.collection("users").doc(uid), legacyMirror, { merge: true });

  await batch.commit();

  await emitShiftActivityIfNeeded(
    db,
    uid,
    userData,
    options.beforeEntry,
    options.afterEntry
  );

  return { week, payPeriod, totalHours, level, streak };
}

module.exports = {
  recomputeUserStats,
  paidHours,
  weeklyStats,
  currentPayCycle,
};
