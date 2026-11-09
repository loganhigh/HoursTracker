"use strict";

// Supporter perks, by total tipped (tipTotal, kept by notifyAdminOnTip).
// Pure: callers pass the users doc; the result is what everyone else sees on
// the public profile, the board rows, chat messages and DM threads.
//
//   any tip  → supporter name colour (blue), badge, chat heart, thanks wall
//   $5 total → choose the name colour
//   $20 total→ animated profile-photo ring
//
// The choices (supporterColor, supporterNameStyle) are written by the user's
// own device; anything not unlocked yet falls back here, so a hand-edited doc
// can't skip ahead.

const COLOR_UNLOCK_TOTAL = 5;
const RING_UNLOCK_TOTAL = 20;
const COLORS = ["blue", "purple", "emerald", "rose"];

function supporterInfo(userData) {
  const data = userData || {};
  const isSupporter = data.isSupporter === true;
  if (!isSupporter) {
    return { isSupporter: false, total: 0, color: "blue", prefersColor: false, ring: false };
  }
  const total = Math.max(0, Math.round((Number(data.tipTotal) || 0) * 100) / 100);
  const wanted = String(data.supporterColor || "blue");
  const color = total >= COLOR_UNLOCK_TOTAL && COLORS.includes(wanted) ? wanted : "blue";
  return {
    isSupporter: true,
    total,
    color,
    // At Legend prestige (P11+) the earned Legend colour shows unless the
    // supporter switched to their supporter colour.
    prefersColor: data.supporterNameStyle === "supporter",
    ring: total >= RING_UNLOCK_TOTAL,
  };
}

const SUPPORTER_BADGE = {
  icon: "heart.fill",
  name: "Supporter",
  detail: "Helped keep Hour Tracker running",
  isLegend: false,
  order: 9000,
};

function withSupporterBadge(summaries, isSupporter) {
  const rest = (Array.isArray(summaries) ? summaries : []).filter((b) => !(b && b.name === SUPPORTER_BADGE.name));
  return isSupporter ? [...rest, { ...SUPPORTER_BADGE }] : rest;
}

module.exports = { supporterInfo, withSupporterBadge, SUPPORTER_BADGE, COLOR_UNLOCK_TOTAL, RING_UNLOCK_TOTAL, COLORS };
