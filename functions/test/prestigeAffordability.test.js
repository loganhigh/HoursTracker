const test = require("node:test");
const assert = require("node:assert/strict");
const { prestigeAffordability } = require("../src/stats/recompute.js");

const RUN = 86322; // sum of xpRequiredForLevel(1..25)

test("prestige 0 is never corrected", () => {
  assert.equal(prestigeAffordability({ prestige: 0, publishedTotalXP: 0, trackedTotalXP: 0 }).corrected, false);
});

test("double-prestige signature (P3 on two runs of XP) corrects down to P2", () => {
  // Joey, 2026-09-22: prestige 3, published 207825, tracked 207825.
  const d = prestigeAffordability({
    prestige: 3, publishedTotalXP: 207825, trackedTotalXP: 207825, hourSnapshots: [310.5, 612.25, 612.25],
  });
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
  const d = prestigeAffordability({
    prestige: 4, publishedTotalXP: RUN + 10, trackedTotalXP: 2 * RUN + 10, hourSnapshots: [100, 100, 100, 400],
  });
  assert.deepEqual(d, { corrected: true, prestige: 2, reason: "unaffordable" });
});

test("expired challenge XP never demotes a prestige earned hundreds of hours apart", () => {
  // Logan, 2026-09-28: P4 earned at 345409; daily challenge XP (1800) reset
  // overnight → 343609, 1679 short of 4 runs. Hour snapshots are all distinct.
  const d = prestigeAffordability({
    prestige: 4, publishedTotalXP: 343609, trackedTotalXP: 343609,
    hourSnapshots: [332.9, 665.8, 1078.3, 1494.55],
  });
  assert.deepEqual(d, { corrected: false, prestige: 4, reason: "no-double-tap" });
});

test("missing hour snapshots are not evidence of a double tap", () => {
  const d = prestigeAffordability({ prestige: 3, publishedTotalXP: 207825, trackedTotalXP: 207825 });
  assert.equal(d.corrected, false);
});

test("only the duplicated prestiges are removed, even when XP is further short", () => {
  // One double tap, but XP only covers one run: remove just the duplicate.
  const d = prestigeAffordability({
    prestige: 3, publishedTotalXP: RUN + 10, trackedTotalXP: 0, hourSnapshots: [300, 700, 700],
  });
  assert.deepEqual(d, { corrected: true, prestige: 2, reason: "unaffordable" });
});
