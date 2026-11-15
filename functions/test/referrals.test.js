const test = require("node:test");
const assert = require("node:assert");
const r = require("../src/social/referrals");

const now = Date.parse("2026-11-15T12:00:00Z");
const day = 86_400_000;

test("new account within two weeks can be credited once", () => {
  const base = { myUid: "a", referrerUid: "b", nowMs: now };
  assert.equal(r.canClaimReferral({ ...base, accountCreatedMs: now - 3 * day }), true);
  assert.equal(r.canClaimReferral({ ...base, accountCreatedMs: now - 15 * day }), false);
  assert.equal(r.canClaimReferral({ ...base, accountCreatedMs: now - day, alreadyReferredBy: "c" }), false);
  assert.equal(r.canClaimReferral({ ...base, referrerUid: "a", accountCreatedMs: now - day }), false);
  assert.equal(r.canClaimReferral({ ...base, accountCreatedMs: NaN }), false);
});

test("one Recruiter badge", () => {
  assert.equal(r.referralTier(0), null);
  assert.equal(r.referralTier(1).name, "Recruiter");
  assert.equal(r.referralTier(12).name, "Recruiter");
  assert.equal(r.nextReferralTier(0).name, "Recruiter");
  assert.equal(r.nextReferralTier(1), null);
  const badges = r.withReferralBadge([{ name: "Recruiter" }, { name: "Streak" }], 3);
  assert.deepEqual(badges.map((b) => b.name), ["Streak", "Recruiter"]);
  assert.deepEqual(r.withReferralBadge([{ name: "Recruiter" }], 0), []);
});
