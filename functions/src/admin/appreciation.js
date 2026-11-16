"use strict";

// "Thank you" pushes for the most active users, sent by hand from Admin →
// Top Active Users. Never spammy: one per person per 90 days at most, and
// only while they're still using the app (opened it or logged a shift in the
// last 7 days). State lives in _appreciation/{uid}.

const DAY_MS = 86_400_000;
const APPRECIATION_COOLDOWN_MS = 90 * DAY_MS;
const STILL_ACTIVE_MS = 7 * DAY_MS;

function lastTouchMs(row) {
  return Math.max(Number(row?.lastActiveAt) || 0, Number(row?.lastShiftMs) || 0);
}

/**
 * Whether a thank-you can go out now.
 * { allowed, reason: "ok" | "cooldown" | "inactive", nextAllowedMs }
 */
function appreciationStatus(state, row, nowMs) {
  const last = Number(state?.lastThanksMs) || 0;
  const nextAllowedMs = last ? last + APPRECIATION_COOLDOWN_MS : null;
  if (last && nowMs < nextAllowedMs) return { allowed: false, reason: "cooldown", nextAllowedMs };
  const touch = lastTouchMs(row);
  if (!touch || nowMs - touch > STILL_ACTIVE_MS) return { allowed: false, reason: "inactive", nextAllowedMs };
  return { allowed: true, reason: "ok", nextAllowedMs };
}

function fmtHours(h) {
  const n = Math.round(Number(h) || 0);
  return n.toLocaleString("en-US");
}

/** Default copy, built from the user's own numbers. */
function appreciationMessage(row) {
  const hours = Number(row?.totalHours) || 0;
  const name = String(row?.displayName || "").trim();
  return {
    title: name ? `Thank you, ${name}` : "Thank you for tracking with us",
    body: hours >= 1
      ? `You've logged ${fmtHours(hours)} hours with Hour Tracker. Thanks for using the app as much as you do. It means a lot.`
      : "Thanks for using Hour Tracker as much as you do. It means a lot.",
  };
}

module.exports = {
  APPRECIATION_COOLDOWN_MS,
  STILL_ACTIVE_MS,
  appreciationStatus,
  appreciationMessage,
};
