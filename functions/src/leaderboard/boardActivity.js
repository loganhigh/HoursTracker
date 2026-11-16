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

module.exports = {
  BOARD_INACTIVE_MS,
  toMs,
  lastActivityMs,
  isInactiveForBoard,
  withoutUids,
};
