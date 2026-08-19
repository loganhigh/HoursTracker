/**
 * Pure analytics logic for the Admin command center: the activity score,
 * at-risk detection, and signup bucketing. No I/O — index.js assembles rows
 * (publicProfiles + auth + presence) and hands them in, which keeps every
 * rule here unit-testable (see test/adminAnalytics.test.js).
 *
 * Every signal used here actually exists in the backend: presence stamps,
 * lastShiftLoggedAt, the server-computed weekly/streak fields, auth creation
 * times. Nothing is estimated from data we don't track — that's why there is
 * deliberately no retention module and no per-period XP.
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
  if (inactiveDays < 3) return null;

  const reasons = [`No activity for ${inactiveDays} days`];
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

module.exports = {
  DAY_MS,
  activityScore,
  atRiskInfo,
  signupBuckets,
  countWithin,
  startOfUTCDay,
};
