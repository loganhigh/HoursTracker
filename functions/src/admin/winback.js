/**
 * Win-back pushes for at-risk users — pure decision logic, no I/O
 * (index.js `winbackDaily` / `adminSendWinbackNudge` do the reads and sends;
 * see test/winback.test.js).
 *
 * At most two automatic pushes per quiet stretch, then silence until the
 * user comes back (a new stretch starts the sequence over):
 *   1. once they are past their usual break (min 7 days quiet)
 *   2. two weeks after that (min 21 days quiet) — the last one
 * Someone already gone 45+ days when the sequence would start is left alone.
 */

const { DAY_MS, atRiskInfo } = require("./analytics");

const MAX_START_DAYS = 45;
const MANUAL_COOLDOWN_MS = 7 * DAY_MS;

function lastTouchMs(row) {
  return Math.max(row.lastActiveAt || 0, row.lastShiftMs || 0, row.createdAt || 0);
}

/** Days quiet before push 1 and push 2, stretched for long usual breaks. */
function thresholds(row) {
  const gap = Number(row.typicalGapDays) || 0;
  const first = Math.max(7, gap + 4);
  return { first, second: Math.max(21, first + 14) };
}

/**
 * What to do for this user today. `state` is their `_winback/{uid}` doc
 * ({quietSinceMs, stage}) or null. Returns { send: 0|1|2, quietSinceMs,
 * inactiveDays } — send 0 means nothing today.
 */
function winbackDecision(row, state, nowMs) {
  const quietSinceMs = lastTouchMs(row);
  const none = { send: 0, quietSinceMs, inactiveDays: 0 };
  // Never push before the user's usual break has been measured — otherwise
  // a seasonal worker could be nudged mid-break on the first run.
  if (row.typicalGapDays === undefined) return none;
  if (!atRiskInfo(row, nowMs) || quietSinceMs <= 0) return none;

  const inactiveDays = Math.floor((nowMs - quietSinceMs) / DAY_MS);
  // A different quiet stretch than the one recorded = they came back since.
  const stage = state && state.quietSinceMs === quietSinceMs ? Number(state.stage) || 0 : 0;
  const t = thresholds(row);

  if (stage === 0) {
    if (inactiveDays >= MAX_START_DAYS || inactiveDays < t.first) return { ...none, inactiveDays };
    return { send: 1, quietSinceMs, inactiveDays };
  }
  if (stage === 1 && inactiveDays >= t.second) {
    return { send: 2, quietSinceMs, inactiveDays };
  }
  return { ...none, inactiveDays };
}

function fmtHours(h) {
  return Math.round(Number(h) || 0).toLocaleString("en-US");
}

/** Push copy built from the user's own numbers. */
function winbackMessage(row, stage) {
  const hours = Number(row.totalHours) || 0;
  const best = Number(row.bestStreak) || 0;
  if (stage === 2) {
    return {
      title: "Still tracking your hours?",
      body: best >= 5
        ? `Your ${best}-day best streak is still there to beat. Log your latest shift in a few seconds.`
        : `Pick up where you left off — your ${fmtHours(hours)} hours are saved. Log your latest shift in a few seconds.`,
    };
  }
  return {
    title: "Don't miss a paycheque's worth of hours",
    body: `You've tracked ${fmtHours(hours)} hours with Hour Tracker. Add your recent shifts so this cheque adds up.`,
  };
}

/** Manual admin nudge: allowed once a week per user. */
function manualNudgeAllowed(state, nowMs) {
  const last = Number(state?.lastManualMs) || 0;
  return nowMs - last >= MANUAL_COOLDOWN_MS;
}

/**
 * The 90th-percentile gap (in days) between consecutive worked days in the
 * last 365 days; null with too little history to say. `days` are sorted
 * "yyyy-MM-dd" strings.
 */
function typicalGapDays(days, nowMs) {
  const cutoff = nowMs - 365 * DAY_MS;
  const nums = days
    .map((iso) => {
      const [y, m, d] = iso.split("-").map(Number);
      return Date.UTC(y, m - 1, d);
    })
    .filter((ms) => ms >= cutoff)
    .map((ms) => Math.round(ms / DAY_MS));
  if (nums.length < 6) return null;
  const gaps = [];
  for (let i = 1; i < nums.length; i++) gaps.push(nums[i] - nums[i - 1]);
  gaps.sort((a, b) => a - b);
  return gaps[Math.min(gaps.length - 1, Math.floor(gaps.length * 0.9))];
}

module.exports = {
  MAX_START_DAYS,
  MANUAL_COOLDOWN_MS,
  thresholds,
  winbackDecision,
  winbackMessage,
  manualNudgeAllowed,
  typicalGapDays,
};
