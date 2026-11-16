/**
 * Pure analytics logic for the Admin command center: the activity score,
 * at-risk detection, and signup bucketing. No I/O — index.js assembles rows
 * (publicProfiles + auth + presence) and hands them in, which keeps every
 * rule here unit-testable (see test/adminAnalytics.test.js).
 *
 * Every signal used here actually exists in the backend: presence stamps,
 * lastShiftLoggedAt, the server-computed weekly/streak fields, auth creation
 * times. Nothing is estimated from data we don't track: week-one retention is
 * counted from the shifts each new account actually logged.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Engagement score 0–100, weighted hard toward the present:
 *   35 — how recently they touched the app (linear decay to 0 over 7 days)
 *   25 — shifts logged this week (full marks at 5)
 *   20 — hours logged this week (full marks at 40)
 *   10 — current streak (full marks at 7 days)
 *   10 — logged a shift today
 * Lifetime hours are deliberately absent: 2,000 career hours plus a month of
 * silence should lose to someone logging every day.
 */
function activityScore(row, nowMs) {
  const lastTouchMs = Math.max(row.lastActiveAt || 0, row.lastShiftMs || 0);
  let score = 0;

  if (lastTouchMs > 0) {
    const daysAgo = Math.max(0, (nowMs - lastTouchMs) / DAY_MS);
    score += Math.max(0, 35 * (1 - daysAgo / 7));
  }
  score += 25 * Math.min((row.weeklyShifts || 0) / 5, 1);
  score += 20 * Math.min((row.weeklyHours || 0) / 40, 1);
  score += 10 * Math.min((row.currentStreak || 0) / 7, 1);

  const todayStart = startOfUTCDay(nowMs);
  if ((row.lastShiftMs || 0) >= todayStart) score += 10;

  return Math.round(Math.min(100, score));
}

/**
 * At-risk = was genuinely active once, now going quiet. Returns null for
 * users who never really used the app (nothing to lose) or who are still
 * active. Reasons are grounded in recorded behaviour only.
 */
function atRiskInfo(row, nowMs) {
  const previouslyActive = (row.totalHours || 0) >= 10 || (row.bestStreak || 0) >= 3;
  if (!previouslyActive) return null;

  const lastTouchMs = Math.max(row.lastActiveAt || 0, row.lastShiftMs || 0, row.createdAt || 0);
  if (lastTouchMs <= 0) return null;
  const inactiveDays = Math.floor((nowMs - lastTouchMs) / DAY_MS);
  // Seasonal / rotational workers routinely go quiet between jobs: a gap
  // inside their usual break (typicalGapDays, the 90th-percentile gap
  // between worked days over the last year) isn't a warning sign yet.
  const usualGap = Number(row.typicalGapDays) || 0;
  if (inactiveDays < Math.max(3, usualGap + 3)) return null;

  const reasons = [`No activity for ${inactiveDays} days`];
  if (usualGap >= 7) reasons.push(`Usually back within ${usualGap} days`);
  if ((row.bestStreak || 0) >= 5 && (row.currentStreak || 0) === 0) {
    reasons.push(`${row.bestStreak}-day best streak ended`);
  }
  if ((row.weeklyShifts || 0) === 0 && (row.totalHours || 0) >= 20) {
    reasons.push("0 shifts this week");
  }
  return { inactiveDays, reasons };
}

/** Signups per UTC day for the trailing `days`, oldest first. */
function signupBuckets(creationTimesMs, days, nowMs) {
  const buckets = [];
  const todayStart = startOfUTCDay(nowMs);
  for (let i = days - 1; i >= 0; i--) {
    const dayStart = todayStart - i * DAY_MS;
    buckets.push({ dayStartMs: dayStart, count: 0 });
  }
  const firstStart = buckets[0]?.dayStartMs ?? todayStart;
  for (const ms of creationTimesMs) {
    if (!Number.isFinite(ms) || ms < firstStart) continue;
    const index = Math.floor((ms - firstStart) / DAY_MS);
    if (index >= 0 && index < buckets.length) buckets[index].count += 1;
  }
  return buckets;
}

/** Count of rows whose timestamp field is within `days` of now. */
function countWithin(rows, field, days, nowMs) {
  const cutoff = nowMs - days * DAY_MS;
  return rows.filter((r) => Number.isFinite(r[field]) && r[field] >= cutoff).length;
}

function startOfUTCDay(nowMs) {
  const d = new Date(nowMs);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}

/** Latest touch: app open or logged shift (0 when neither). */
function lastTouchMs(row) {
  return Math.max(Number(row.lastActiveAt) || 0, Number(row.lastShiftMs) || 0);
}

/**
 * Which activity bucket a user is in:
 *   "never"  — signed up, never logged a shift
 *   "active" — opened the app or logged within 7 days
 *   "quiet"  — last seen 7–30 days ago
 *   "gone"   — nothing for 30+ days (off the leaderboard until they return)
 */
function activityBucket(row, nowMs) {
  const hasShifts = (Number(row.realHours ?? row.totalHours) || 0) > 0 || (Number(row.lastShiftMs) || 0) > 0;
  if (!hasShifts) return "never";
  const touch = lastTouchMs(row) || Number(row.createdAt) || 0;
  if (touch <= 0) return "gone";
  const days = (nowMs - touch) / DAY_MS;
  if (days <= 7) return "active";
  if (days <= 30) return "quiet";
  return "gone";
}

/** Rows grouped by activityBucket, each list most recently seen first. */
function activityBreakdown(rows, nowMs) {
  const out = { active: [], quiet: [], gone: [], never: [] };
  for (const r of rows) out[activityBucket(r, nowMs)].push(r);
  const recent = (a, b) => (lastTouchMs(b) || b.createdAt || 0) - (lastTouchMs(a) || a.createdAt || 0);
  for (const k of Object.keys(out)) out[k].sort(recent);
  return out;
}

/** Monday 00:00 UTC of the week containing `ms`. */
function startOfUTCWeek(ms) {
  const day = startOfUTCDay(ms);
  const weekday = new Date(day).getUTCDay(); // 0 Sun
  return day - ((weekday + 6) % 7) * DAY_MS;
}

/**
 * Week-one retention per weekly signup cohort, oldest first.
 * users: [{ createdAt, shiftDatesMs: [ms], lastTouchMs }]
 * A user "hit the goal" when they logged shifts on 3+ different days within
 * the first 7 days of their account. Cohorts whose newest member is still in
 * week one are flagged `complete: false` (their numbers can still rise).
 */
function weekOneCohorts(users, nowMs, weeks = 8, goalDays = 3) {
  const thisWeek = startOfUTCWeek(nowMs);
  const cohorts = [];
  for (let i = weeks - 1; i >= 0; i--) {
    const start = thisWeek - i * 7 * DAY_MS;
    cohorts.push({ weekStartMs: start, signups: 0, loggedAny: 0, hitGoal: 0, activeNow: 0, complete: start + 14 * DAY_MS <= nowMs });
  }
  const first = cohorts[0].weekStartMs;
  for (const u of users) {
    const created = Number(u.createdAt);
    if (!Number.isFinite(created) || created < first) continue;
    const c = cohorts[Math.floor((created - first) / (7 * DAY_MS))];
    if (!c) continue;
    c.signups += 1;
    const createdDay = startOfUTCDay(created);
    const days = new Set();
    for (const ms of u.shiftDatesMs || []) {
      const offset = Math.floor((startOfUTCDay(ms) - createdDay) / DAY_MS);
      if (offset >= 0 && offset < 7) days.add(offset);
    }
    if (days.size > 0) c.loggedAny += 1;
    if (days.size >= goalDays) c.hitGoal += 1;
    if ((Number(u.lastTouchMs) || 0) >= nowMs - 7 * DAY_MS) c.activeNow += 1;
  }
  return cohorts;
}

module.exports = {
  DAY_MS,
  lastTouchMs,
  activityBucket,
  activityBreakdown,
  startOfUTCWeek,
  weekOneCohorts,
  activityScore,
  atRiskInfo,
  signupBuckets,
  countWithin,
  startOfUTCDay,
};
