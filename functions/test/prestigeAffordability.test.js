const test = require("node:test");
const assert = require("node:assert/strict");
const { prestigeAffordability } = require("../src/stats/recompute.js");

const RUN = 86322; // sum of xpRequiredForLevel(1..25)

test("prestige 0 is never corrected", () => {
  assert.equal(prestigeAffordability({ prestige: 0, publishedTotalXP: 0, trackedTotalXP: 0 }).corrected, false);
});

test("double-prestige signature (P3 on two runs of XP) corrects down to P2", () => {
  // Joey, 2026-09-22: prestige 3, published 207825, tracked 207825.
  const d = prestigeAffordability({ prestige: 3, publishedTotalXP: 207825, trackedTotalXP: 207825 });
  assert.deepEqual(d, { corrected: true, prestige: 2, reason: "unaffordable" });
});

test("a legitimately earned prestige is untouched, banked surplus included", () => {
  assert.equal(prestigeAffordability({ prestige: 2, publishedTotalXP: 2 * RUN, trackedTotalXP: 0 }).corrected, false);
  assert.equal(prestigeAffordability({ prestige: 2, publishedTotalXP: 2 * RUN + 40000, trackedTotalXP: 0 }).corrected, false);
});

test("either total covering the prestige is enough (transient low client push)", () => {
  // Device pushed a low total but Firestore entries vouch for the prestige.
  const d = prestigeAffordability({ prestige: 3, publishedTotalXP: 1000, trackedTotalXP: 3 * RUN + 5 });
  assert.equal(d.corrected, false);
});

test("zero XP with a prestige is left alone as an anomaly", () => {
  const d = prestigeAffordability({ prestige: 10, publishedTotalXP: 0, trackedTotalXP: 0 });
  assert.deepEqual(d, { corrected: false, prestige: 10, reason: "zero-xp" });
});

test("legacy admin prestige floor exempts the account", () => {
  const d = prestigeAffordability({ prestige: 5, publishedTotalXP: 100, trackedTotalXP: 100, adminFloorPrestige: 5 });
  assert.deepEqual(d, { corrected: false, prestige: 5, reason: "admin-floor" });
});

test("correction uses the better of the two totals", () => {
  const d = prestigeAffordability({ prestige: 4, publishedTotalXP: RUN + 10, trackedTotalXP: 2 * RUN + 10 });
  assert.deepEqual(d, { corrected: true, prestige: 2, reason: "unaffordable" });
});
