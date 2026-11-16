"use strict";

// Inactive users leave the global leaderboard until they come back.
//
// "Active" = opened the app (presence/{uid}.lastActiveAt) or logged a shift
// (boardHours/{uid}.lastShiftMs, falling back to the public
// lastShiftLoggedAt) within the last 30 days. Nothing is deleted: their hours
// stay in boardHours, so the next 15-minute rebuild after they open the app or
// log a shift puts them straight back at their real rank.
//
// A user with no activity signal at all is kept (missing data never hides
// anyone; every current build stamps presence on launch).

const BOARD_INACTIVE_MS = 30 * 86_400_000;

function toMs(value) {
  if (value == null) return 0;
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return 0;
}

/** Latest activity across the signals we have (0 when none). */
function lastActivityMs({ presenceMs, lastShiftMs, profileLastShift } = {}) {
  return Math.max(toMs(presenceMs), toMs(lastShiftMs), toMs(profileLastShift));
}

/** True when the user should be left off the board right now. */
function isInactiveForBoard(activityMs, nowMs, windowMs = BOARD_INACTIVE_MS) {
  const ms = toMs(activityMs);
  if (ms <= 0) return false;
  return nowMs - ms > windowMs;
}

/**
 * The previous broadcast with `droppedUids` removed and re-ranked, so a
 * cleanup that hides inactive users doesn't read as everyone below them
 * "climbing" (which would send rank-up pushes nobody earned).
 */
function withoutUids(rows, droppedUids) {
  if (!Array.isArray(rows)) return [];
  if (!droppedUids || droppedUids.size === 0) return rows;
  return rows
    .filter((r) => r && !droppedUids.has(r.uid))
    .map((r, i) => ({ ...r, rank: i + 1 }));
}

// ── Day-27 warning ────────────────────────────────────────────────────────
// One push per quiet stretch, a few days before someone drops off:
// "Log a shift to keep your spot on the leaderboard."

const WARN_AT_DAYS = 27;
const DAY_MS = 86_400_000;
const BOARD_DAYS = BOARD_INACTIVE_MS / DAY_MS;

/**
 * Whether to send the keep-your-spot push today. `warnedQuietSinceMs` is the
 * quiet stretch already warned about (from _winback/{uid}), so a stretch is
 * warned once; coming back starts a new stretch.
 */
function boardWarningDecision({ activityMs, onBoard, warnedQuietSinceMs, nowMs }) {
  const quietSinceMs = toMs(activityMs);
  const none = { send: false, quietSinceMs, daysLeft: 0 };
  if (!onBoard || quietSinceMs <= 0) return none;
  if (warnedQuietSinceMs && Number(warnedQuietSinceMs) === quietSinceMs) return none;
  const days = Math.floor((nowMs - quietSinceMs) / DAY_MS);
  if (days < WARN_AT_DAYS || days >= BOARD_DAYS) return none;
  return { send: true, quietSinceMs, daysLeft: BOARD_DAYS - days };
}

function boardWarningMessage(rank, daysLeft) {
  const left = daysLeft === 1 ? "tomorrow" : `in ${daysLeft} days`;
  return {
    title: `Your leaderboard spot ends ${left}`,
    body: Number(rank) > 0
      ? `You're #${rank} on the leaderboard. Log a shift or open Hour Tracker to keep your spot.`
      : "Log a shift or open Hour Tracker to stay on the leaderboard.",
  };
}

// ── Coming back ───────────────────────────────────────────────────────────
// _leaderboardPrivate/inactive = { uids: {uid: hiddenSinceMs},
//   returned: {uid: {rank, atMs}} }. A uid that was hidden and is ranked
// again lands in `returned` until the app shows the welcome-back card.

const RETURNED_TTL_MS = 3 * DAY_MS;

/** Next inactive-state doc after a full rebuild. */
function nextInactiveState(prev, inactiveUids, rankByUid, nowMs) {
  const prevUids = (prev && prev.uids) || {};
  const uids = {};
  for (const uid of inactiveUids) uids[uid] = Number(prevUids[uid]) || nowMs;
  const returned = {};
  for (const [uid, r] of Object.entries((prev && prev.returned) || {})) {
    if (nowMs - (Number(r?.atMs) || 0) < RETURNED_TTL_MS && !inactiveUids.has(uid)) returned[uid] = r;
  }
  for (const uid of Object.keys(prevUids)) {
    if (inactiveUids.has(uid)) continue;
    returned[uid] = { rank: rankByUid.get(uid) || null, atMs: nowMs };
  }
  return { uids, returned };
}

module.exports = {
  BOARD_INACTIVE_MS,
  WARN_AT_DAYS,
  RETURNED_TTL_MS,
  boardWarningDecision,
  boardWarningMessage,
  nextInactiveState,
  toMs,
  lastActivityMs,
  isInactiveForBoard,
  withoutUids,
};
