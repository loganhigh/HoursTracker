"use strict";

// Invite rewards. A new account that adds a friend from that friend's invite
// link (hourtracking.online/f/<username>) is "referred by" them; the inviter
// earns the Recruiter badge.
//
// Credit is given once per new account, only within its first two weeks, and
// never to yourself. referredBy / referralCount are server-owned (rules block
// client writes), so a hand-edited doc can't fake it.

const CLAIM_WINDOW_MS = 14 * 86_400_000;

// One invite badge.
const TIERS = [
  { min: 1, icon: "person.badge.plus", name: "Recruiter", detail: "Brought a friend to Hour Tracker" },
];
const BADGE_NAMES = TIERS.map((t) => t.name);

function referralTier(count) {
  const n = Math.max(0, Math.floor(Number(count) || 0));
  return TIERS.find((t) => n >= t.min) || null;
}

/** Next tier above `count` (nil once earned). */
function nextReferralTier(count) {
  const n = Math.max(0, Math.floor(Number(count) || 0));
  return [...TIERS].reverse().find((t) => n < t.min) || null;
}

/** Drops any client-sent invite badge and adds the earned one. */
function withReferralBadge(summaries, count) {
  const rest = (Array.isArray(summaries) ? summaries : [])
    .filter((b) => !(b && BADGE_NAMES.includes(b.name)));
  const tier = referralTier(count);
  if (!tier) return rest;
  return [...rest, { icon: tier.icon, name: tier.name, detail: tier.detail, isLegend: false, order: 8900 }];
}

/**
 * Whether `myUid` may be credited as referred by `referrerUid` now.
 * accountCreatedMs: Firebase Auth creation time of the new account.
 */
function canClaimReferral({ myUid, referrerUid, accountCreatedMs, nowMs, alreadyReferredBy }) {
  if (!myUid || !referrerUid || myUid === referrerUid) return false;
  if (alreadyReferredBy) return false;
  const created = Number(accountCreatedMs);
  if (!Number.isFinite(created) || created <= 0) return false;
  const age = nowMs - created;
  return age >= 0 && age <= CLAIM_WINDOW_MS;
}

module.exports = {
  CLAIM_WINDOW_MS,
  TIERS,
  referralTier,
  nextReferralTier,
  withReferralBadge,
  canClaimReferral,
};
