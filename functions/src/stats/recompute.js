/**
 * Server-side stats recompute for timeEntries writes.
 * Maintains users/{uid}/stats/*, publicProfiles/*, legacy users/{uid} mirror,
 * and server-written activity events.
 */

const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const MS_DAY = 86400000;

// Titles that are no longer valid equippable titles but may still be sitting in
// old `users/{uid}.equippedTitle` docs (e.g. flavor "rank" names from an earlier
// app version, or a retired milestone). The client never writes these anymore,
// so any doc holding one is stale — strip it here rather than re-publishing it
// to publicProfiles on every recompute.
const LEGACY_INVALID_EQUIPPED_TITLES = new Set([
  "Rookie", "Shift Starter", "Clock Puncher", "Hour Hustler", "Time Tracker",
  "Early Bird", "Daily Grinder", "Break Boss", "Shift Regular", "Week Warrior",
  "Paycheck Hunter", "Schedule Pro", "Hard Charger", "Time Keeper", "Shift Captain",
  "Hours Hero", "Work Warrior", "Clock Commander", "Elite Grinder", "Hour Machine",
  "Shift Legend", "Time Titan", "Overtime Ace", "OT King", "Prestige Ready",
  "Level 10 Veteran",
]);

function sanitizedEquippedTitle(rawTitle) {
  if (!rawTitle || LEGACY_INVALID_EQUIPPED_TITLES.has(rawTitle)) return "";
  return rawTitle;
}

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

const MIN_REASONABLE_PAY_BOUNDARY_YEAR = 2020;
const MAX_REASONABLE_PAY_BOUNDARY_YEARS_AHEAD = 5;

function payBoundaryDate(value, now = new Date()) {
  const ms = toMs(value);
  if (ms == null) return null;
  const date = new Date(ms);
  if (Number.isNaN(date.getTime())) return null;
  if (date.getFullYear() < MIN_REASONABLE_PAY_BOUNDARY_YEAR) return null;
  const max = new Date(now);
  max.setFullYear(max.getFullYear() + MAX_REASONABLE_PAY_BOUNDARY_YEARS_AHEAD);
  if (date > max) return null;
  return date;
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

function normalizedPaydayBoundary(settings, now = new Date()) {
  const savedPayday = payBoundaryDate(settings.nextPayday, now);
  if (savedPayday) {
    return startOfDay(savedPayday);
  }
  const span = spanDays(settings.payPeriodType || "biWeekly");
  const today = startOfDay(now);
  return new Date(today.getTime() + span * MS_DAY);
}

function usesSavedCutoff(settings, now = new Date()) {
  return settings.payPeriodUsesCutoff === true && payBoundaryDate(settings.nextCutoff, now) != null;
}

function makeCycleFromCutoff(cutoff, settings, now = new Date()) {
  const span = spanDays(settings.payPeriodType || "biWeekly");
  const safeCutoff = payBoundaryDate(cutoff, now) || now;
  const cutoffDay = startOfDay(safeCutoff);
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

// Same defensive principle as MAX_LEVEL_LOOP_ITERATIONS below: a corrupted or
// wildly out-of-range saved date (nextPayday/nextCutoff) shouldn't be able to
// force tens of thousands+ of synchronous iterations rolling the cycle
// forward/backward one span at a time. 20,000 iterations of a 14-day span
// already covers ~750 years either direction, far more than any real date
// bug should need — this exists purely as a hard backstop.
const MAX_CYCLE_LOOP_ITERATIONS = 20_000;

function currentPayCycle(settings, asOf = new Date()) {
  const d = startOfDay(asOf);
  const span = spanDays(settings.payPeriodType || "biWeekly");

  if (usesSavedCutoff(settings, d)) {
    let cutoff = startOfDay(payBoundaryDate(settings.nextCutoff, d));
    let cycle = makeCycleFromCutoff(cutoff, settings, d);
    let guard = 0;
    while (d < cycle.start && guard++ < MAX_CYCLE_LOOP_ITERATIONS) {
      cutoff = new Date(cutoff.getTime() - span * MS_DAY);
      cycle = makeCycleFromCutoff(cutoff, settings, d);
    }
    guard = 0;
    while (d >= cycle.end && guard++ < MAX_CYCLE_LOOP_ITERATIONS) {
      cutoff = new Date(cutoff.getTime() + span * MS_DAY);
      cycle = makeCycleFromCutoff(cutoff, settings, d);
    }
    return cycle;
  }

  let payday = normalizedPaydayBoundary(settings, d);
  let cycle = makeCycle(payday, settings);
  let guard = 0;
  while (d < cycle.start && guard++ < MAX_CYCLE_LOOP_ITERATIONS) {
    payday = new Date(payday.getTime() - span * MS_DAY);
    cycle = makeCycle(payday, settings);
  }
  guard = 0;
  while (d >= cycle.end && guard++ < MAX_CYCLE_LOOP_ITERATIONS) {
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

// Hard ceiling on prestige/level math inputs. Without this, a single
// corrupted `prestige` or `totalXP` value (e.g. a stray huge number written
// by a client bug or a bad manual Firestore edit) turns `maxLevel` and/or the
// loop below into something that can iterate for an extremely long time —
// which, being fully synchronous, blocks Node's single-threaded event loop
// entirely. That doesn't just slow this one user down: it freezes the whole
// process, so nothing else can run either — not even the bulk refresh's own
// per-user timeout, since that also needs the event loop to fire. This is
// the confirmed cause of a bulk refresh silently hanging forever on one uid
// with zero error output (a real crash would at least log something; a
// frozen event loop logs nothing because JS itself never gets control back).
const MAX_SANE_PRESTIGE = 500;
const MAX_SANE_TOTAL_XP = 50_000_000;
const MAX_LEVEL_LOOP_ITERATIONS = 10_000;
/** Matches iOS `GamificationLevelCalculator.maxLevelForPrestige` (25). */
const CLIENT_MAX_LEVEL = 25;

/** Matches iOS `GamificationLevelCalculator.xpRequiredForLevel`. */
function xpRequiredForLevel(level) {
  const l = Math.max(1, level);
  return Math.floor(900 + (l - 1) * 180 + Math.pow(l - 1, 1.22) * 18);
}

function totalXPForFullPrestigeRun() {
  let total = 0;
  for (let l = 1; l <= CLIENT_MAX_LEVEL; l++) {
    total += xpRequiredForLevel(l);
  }
  return total;
}

/**
 * Matches iOS `GamificationLevelCalculator.levelState` — prestige-aware level
 * from lifetime XP + optional per-prestige snapshot anchors.
 */
function levelStateFromXP(totalXP, prestige = 0, snapshots = []) {
  const clampedPrestige = Math.min(Math.max(0, Number(prestige) || 0), 10);
  let xpPool = Math.min(MAX_SANE_TOTAL_XP, Math.max(0, Number(totalXP) || 0));

  for (let p = 0; p < clampedPrestige; p++) {
    let runXP;
    if (p < snapshots.length) {
      const snap = Number(snapshots[p]) || 0;
      const prev = p > 0 ? Number(snapshots[p - 1]) || 0 : 0;
      runXP = snap - prev;
    } else {
      runXP = totalXPForFullPrestigeRun();
    }
    xpPool = Math.max(0, xpPool - runXP);
  }

  const maxLevel = CLIENT_MAX_LEVEL;
  const xpPerRun = totalXPForFullPrestigeRun();
  const cappedRunXP = Math.min(xpPool, xpPerRun);
  let remaining = cappedRunXP;
  let level = 1;
  while (level < maxLevel) {
    const needed = xpRequiredForLevel(level);
    if (remaining >= needed) {
      remaining -= needed;
      level += 1;
    } else {
      break;
    }
  }
  return Math.min(level, maxLevel);
}

function totalXPAtLevelStart(targetLevel, prestige = 0, snapshots = []) {
  const clampedLevel = Math.min(
    Math.max(1, Number(targetLevel) || 1),
    CLIENT_MAX_LEVEL
  );
  const clampedPrestige = Math.min(Math.max(0, Number(prestige) || 0), 10);
  let total = 0;
  const clean = Array.isArray(snapshots)
    ? snapshots.map((v) => Number(v) || 0)
    : [];
  for (let p = 0; p < clampedPrestige; p++) {
    if (p < clean.length) {
      const snap = clean[p];
      const prev = p > 0 ? clean[p - 1] : 0;
      total += snap - prev;
    } else {
      total += totalXPForFullPrestigeRun();
    }
  }
  for (let l = 1; l < clampedLevel; l++) {
    total += xpRequiredForLevel(l);
  }
  return total;
}

function buildSnapshotsForPrestige(prestige) {
  const p = Math.min(Math.max(0, Math.floor(Number(prestige) || 0)), 10);
  const snaps = [];
  let cumulative = 0;
  const runXP = totalXPForFullPrestigeRun();
  for (let i = 0; i < p; i++) {
    cumulative += runXP;
    snaps.push(cumulative);
  }
  return snaps;
}

/** Shift-only prestige/level from entry XP (no admin offset). */
function deriveProgressionFromEntryXP(entryXP) {
  const runXP = totalXPForFullPrestigeRun();
  let pool = Math.max(0, Number(entryXP) || 0);
  const snapshots = [];
  let prestige = 0;
  let cumulative = 0;
  while (prestige < 10 && pool >= runXP) {
    cumulative += runXP;
    prestige += 1;
    pool -= runXP;
    snapshots.push(cumulative);
  }
  const level = levelStateFromXP(Math.max(0, Number(entryXP) || 0), prestige, snapshots);
  return { prestige, snapshots, level };
}

/** Drop prestige snapshots that inflate level after a bad sync/admin save. */
function sanitizedPrestigeSnapshots(totalXP, prestige, snapshots) {
  const clean = Array.isArray(snapshots)
    ? snapshots.map((v) => Number(v) || 0)
    : [];
  if (prestige <= 0 || clean.length === 0) return { snapshots: clean, cleared: false };
  const withSnaps = levelStateFromXP(totalXP, prestige, clean);
  const withoutSnaps = levelStateFromXP(totalXP, prestige, []);
  if (withSnaps > withoutSnaps) {
    return { snapshots: [], cleared: true };
  }
  return { snapshots: clean, cleared: false };
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
  // `timeEntries` is the authoritative source — it's the collection the client
  // reads, writes, edits, and deletes from. The legacy `entries` mirror is only
  // dual-written/deleted when the (now-off-by-default) legacy-mirror flag is on,
  // so `entries` accumulates STALE copies of shifts that were later deleted or
  // edited. Merging both collections would resurrect those deleted shifts and
  // over-count hours (a friend seeing a higher cheque total than the user's own
  // device). So: use `timeEntries` whenever it has any docs; fall back to the
  // legacy `entries` collection ONLY for accounts that never migrated (i.e.
  // have no timeEntries at all).
  const primary = await db.collection("users").doc(uid).collection("timeEntries").get();
  if (!primary.empty) {
    return primary.docs.map((d) => ({ id: d.id, ...d.data() }));
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
  const userRef = db.collection("users").doc(uid);
  const skipFence = options.skipFence === true;

  // Fencing token: when many timeEntries writes land in a short burst (e.g. a
  // client re-syncing a batch of local entries after reinstall), Firestore
  // fires ONE trigger invocation per write, all racing concurrently. Each
  // reads "all entries as of right now" and independently commits a full
  // snapshot — with no guarantee that the invocation which STARTED last is
  // also the one that FINISHES last. An early invocation that read an
  // incomplete entry list can finish after a later, more-complete one and
  // silently clobber it with stale data. Stamping a monotonic sequence
  // number at the start of each run and re-checking it immediately before
  // commit ensures only the run that is still the most-recently-started one
  // at commit time is allowed to persist — anything superseded bails out.
  // Bulk admin refresh passes skipFence so an active user's live entry writes
  // don't cause the backfill run to silently skip persisting their profile.
  let mySeq = null;
  if (!skipFence) {
    mySeq = await db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      const next = (Number(snap.data()?.statsComputeSeq) || 0) + 1;
      tx.set(userRef, { statsComputeSeq: next }, { merge: true });
      return next;
    });
  }

  const [entries, paySettings, gamification, userSnap] = await Promise.all([
    loadAllTimeEntries(db, uid),
    loadPaySettings(db, uid),
    loadGamification(db, uid),
    userRef.get(),
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

  const totalXP = Math.min(
    MAX_SANE_TOTAL_XP,
    Number(gamification.totalXP) || Number(userData.totalXP) || 0
  );
  // Admin-set floors (written only by the admin panel via adminSetUserProgression).
  // Both act as floors: the published value is never lower, but real XP/prestige
  // progression can still push above them.
  //
  // Every value here is clamped to a sane ceiling. A corrupted prestige/level
  // (e.g. from a bad manual edit or a client-side bug) previously fed straight
  // into levelFromXP's loop, which iterates once per level — an astronomically
  // large prestige turns that into a near-infinite synchronous loop that
  // freezes the whole process (see levelFromXP's comment for the full story).
  const clientPrestige = Math.min(
    MAX_SANE_PRESTIGE,
    Number(gamification.prestige) || Number(userData.prestige) || 0
  );
  const prestige = clientPrestige;
  const snapshotSanitize = sanitizedPrestigeSnapshots(
    totalXP,
    prestige,
    gamification.prestigeXPSnapshots
  );
  const snapshots = snapshotSanitize.snapshots;
  const xpLevel = levelStateFromXP(totalXP, prestige, snapshots);
  const level = Math.min(CLIENT_MAX_LEVEL, xpLevel);
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

  // Current calendar month / year hour totals (for the public single-source doc).
  const monthStart = startOfDay(new Date(now.getFullYear(), now.getMonth(), 1));
  const yearStart = startOfDay(new Date(now.getFullYear(), 0, 1));
  let currentMonthHours = 0;
  let currentYearHours = 0;
  let lastShiftMs = 0;
  for (const entry of entries) {
    if (entry.isOffDay) continue;
    const d = entryDate(entry);
    if (!d) continue;
    const h = paidHours(entry);
    if (d >= yearStart) currentYearHours += h;
    if (d >= monthStart) currentMonthHours += h;
    if (d.getTime() > lastShiftMs) lastShiftMs = d.getTime();
  }

  // Per-day breakdown for the current pay cheque (computed here so it can be
  // written into BOTH the public single-source doc and the legacy mirror).
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

  // The badge list is a client-owned input mirrored on users/{uid}; republish it
  // to the public doc (gated by shareBadges) so friends read ONE document.
  const unlockedBadgeSummaries = privacy.shareBadges && Array.isArray(userData.unlockedBadgeSummaries)
    ? userData.unlockedBadgeSummaries
    : [];

  // publicProfiles/{uid} is the SINGLE SOURCE OF TRUTH friends listen to. It
  // carries every field the friends list + friend profile screen render, so a
  // friend never reads the private users/{uid} doc or recomputes anything. The
  // server (Admin SDK) is the sole writer; clients are denied by security rules.
  const publicProfile = {
    displayName: userData.displayName || "Friend",
    friendCode: userData.friendCode || null,
    level,
    prestige,
    totalXP,
    totalHours: privacy.shareHours ? totalHours : 0,
    chequeHours: privacy.shareHours ? payPeriod.hours : 0,
    weeklyHours: privacy.shareHours ? week.hours : 0,
    weeklyShiftsLogged: privacy.shareHours ? week.shifts : 0,
    weeklyDaysLogged: privacy.shareHours ? week.daysWorked : 0,
    currentMonthHours: privacy.shareHours ? currentMonthHours : 0,
    currentYearHours: privacy.shareHours ? currentYearHours : 0,
    bestStreak: privacy.shareHours ? best : 0,
    currentStreak: privacy.shareHours ? streak : 0,
    lastShiftLoggedAt: privacy.shareHours && lastShiftMs > 0 ? Timestamp.fromMillis(lastShiftMs) : null,
    countryCode: String(userData.countryCode || "").trim().toUpperCase(),
    equippedTitle: userData.adminEquippedTitle || sanitizedEquippedTitle(userData.equippedTitle) || "",
    profilePhotoURL: userData.profilePhotoURL || null,
    privacy: userData.privacy || {},
    acceptInvites: userData.acceptInvites !== false,
    // Company identity is sensitive PII (employer, role, start date) and
    // publicProfiles is readable by any signed-in user for the global
    // leaderboard. Gate it behind the same shareHours privacy flag as the other
    // profile fields so it is not written for users who have not opted in; a
    // subsequent recompute scrubs any value previously written while ungated.
    companyName: privacy.shareHours ? (userData.companyName || "") : "",
    companyOccupation: privacy.shareHours ? (userData.companyOccupation || "") : "",
    companyStartDate: privacy.shareHours ? (userData.companyStartDate || null) : null,
    companyHoursLogged: privacy.shareHours ? companyHoursLogged : 0,
    companyDaysWorked: privacy.shareHours ? companyDaysWorked : 0,
    chequeDailySummary,
    chequeWindowStart: privacy.shareHours ? isoDate(payPeriod.periodStart) : "",
    chequeWindowCutoff: privacy.shareHours ? isoDate(payPeriod.periodEnd) : "",
    unlockedBadgeSummaries,
    badgeCount,
    updatedAt,
  };
  batch.set(db.collection("publicProfiles").doc(uid), publicProfile, { merge: true });

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
  } else {
    // The client no longer writes these fields, so the server is the sole
    // manager — clear them when hours aren't shared to enforce privacy.
    legacyMirror.companyHoursLogged = FieldValue.delete();
    legacyMirror.companyDaysWorked = FieldValue.delete();
    legacyMirror.chequeDailySummary = FieldValue.delete();
    legacyMirror.chequeWindowStart = FieldValue.delete();
    legacyMirror.chequeWindowCutoff = FieldValue.delete();
  }
  batch.set(userRef, legacyMirror, { merge: true });

  if (snapshotSanitize.cleared) {
    batch.update(
      db.collection("users").doc(uid).collection("gamification").doc("current"),
      { prestigeXPSnapshots: FieldValue.delete() }
    );
  }

  // Bail out if a newer recompute has already started since we began — it
  // will (or already did) produce a fresher result, so persisting ours now
  // would only reintroduce the exact staleness this fence exists to prevent.
  if (!skipFence) {
    const latestSnap = await userRef.get();
    const latestSeq = Number(latestSnap.data()?.statsComputeSeq) || 0;
    if (latestSeq !== mySeq) {
      return { week, payPeriod, totalHours, level, streak, skipped: true };
    }
  }

  await batch.commit();

  await emitShiftActivityIfNeeded(
    db,
    uid,
    userData,
    options.beforeEntry,
    options.afterEntry
  );

  // Refresh the global "Top 5 Hour Trackers" board. publicProfiles.totalHours is
  // already 0 for users who turned off hour-sharing, so they're naturally
  // excluded by the hours > 0 filter below. Skippable for bulk callers (e.g.
  // refreshing all users at once) that only need this done ONCE at the end
  // rather than redundantly recomputed after every single user.
  if (!options.skipLeaderboardUpdate) {
    try {
      await updateGlobalLeaderboard(db);
    } catch (err) {
      console.warn("updateGlobalLeaderboard failed:", err?.message || err);
    }
  }

  return { week, payPeriod, totalHours, level, streak };
}

/** First whitespace-delimited token of a display name (privacy: first name only). */
function firstNameOnly(displayName) {
  const trimmed = (displayName || "").trim();
  if (!trimmed) return "Tracker";
  return trimmed.split(/\s+/)[0];
}

/** Fill missing leaderboard country codes from users/{uid}.countryCode. */
async function enrichLeaderboardCountryCodes(db, entries) {
  const missing = entries.filter((e) => !e.countryCode).map((e) => e.uid);
  if (missing.length === 0) return;

  const refs = missing.map((uid) => db.collection("users").doc(uid));
  const snaps = await db.getAll(...refs);
  const byUid = new Map();
  for (const snap of snaps) {
    if (!snap.exists) continue;
    const code = String(snap.data()?.countryCode || "").trim().toUpperCase();
    if (code) byUid.set(snap.id, code);
  }
  for (const entry of entries) {
    if (!entry.countryCode && byUid.has(entry.uid)) {
      entry.countryCode = byUid.get(entry.uid);
    }
  }
}

/**
 * Recompute the global lifetime-hours leaderboard and write it to a single
 * public doc `leaderboards/global`. Every client reads just this one doc.
 * `top` holds the top 5; `all` holds every ranked user (hours > 0).
 */
async function updateGlobalLeaderboard(db) {
  const all = [];
  const pageSize = 500;
  let lastDoc = null;

  while (true) {
    let query = db.collection("publicProfiles").orderBy("totalHours", "desc").limit(pageSize);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }
    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      const data = doc.data() || {};
      const hours = Number(data.totalHours) || 0;
      if (hours <= 0) continue;
      all.push({
        rank: all.length + 1,
        uid: doc.id,
        name: firstNameOnly(data.displayName),
        hours: Math.round(hours * 100) / 100,
        countryCode: data.countryCode || "",
      });
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }

  await enrichLeaderboardCountryCodes(db, all);

  const top = all.slice(0, 5).map(({ uid, name, hours, countryCode }) => ({
    uid,
    name,
    hours,
    countryCode,
  }));

  await db.collection("leaderboards").doc("global").set(
    {
      top,
      all,
      totalRanked: all.length,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: false }
  );
}

module.exports = {
  recomputeUserStats,
  updateGlobalLeaderboard,
  totalXPAtLevelStart,
  buildSnapshotsForPrestige,
  deriveProgressionFromEntryXP,
  levelStateFromXP,
  paidHours,
  weeklyStats,
  currentPayCycle,
};
