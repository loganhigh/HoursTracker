const test = require("node:test");
const assert = require("node:assert/strict");
const {
  MAX_PRESTIGE,
  LEGACY_MAX_PRESTIGE,
  prestigeAffordability,
  buildSnapshotsForPrestige,
  deriveProgressionFromEntryXP,
  levelStateFromXP,
  rankTitle,
} = require("../src/stats/recompute.js");

const RUN = 86322; // sum of xpRequiredForLevel(1..25) — unchanged by the cap raise

test("prestige cap is 20; legacy derivation cap stays 10", () => {
  assert.equal(MAX_PRESTIGE, 20);
  assert.equal(LEGACY_MAX_PRESTIGE, 10);
});

test("run cost is unchanged at 86,322 XP", () => {
  assert.equal(buildSnapshotsForPrestige(1)[0], RUN);
});

test("buildSnapshotsForPrestige(20) builds 20 standard runs and clamps above", () => {
  const snaps = buildSnapshotsForPrestige(20);
  assert.equal(snaps.length, 20);
  assert.equal(snaps[19], 20 * RUN);
  assert.equal(buildSnapshotsForPrestige(25).length, 20);
  assert.equal(buildSnapshotsForPrestige(15).length, 15);
});

test("prestigeAffordability handles Legend prestige (P15)", () => {
  assert.deepEqual(
    prestigeAffordability({ prestige: 15, publishedTotalXP: 15 * RUN, trackedTotalXP: 0 }),
    { corrected: false, prestige: 15, reason: null }
  );
  // Double tap at P15 (14 real runs) corrects to P14, not to the old cap.
  const hours = Array.from({ length: 14 }, (_, i) => (i + 1) * 300);
  hours.push(hours[13]);
  assert.deepEqual(
    prestigeAffordability({ prestige: 15, publishedTotalXP: 14 * RUN + 10, trackedTotalXP: 0, hourSnapshots: hours }),
    { corrected: true, prestige: 14, reason: "unaffordable" }
  );
});

test("level math works past P10", () => {
  const snaps = buildSnapshotsForPrestige(15);
  assert.equal(levelStateFromXP(15 * RUN, 15, snaps), 1);
  // Previously clamped to 10 runs, this reported a maxed level 25.
  assert.equal(levelStateFromXP(15 * RUN + 900, 15, snaps), 2);
});

test("deriving from XP never auto-promotes past the legacy cap by default", () => {
  const d = deriveProgressionFromEntryXP(14 * RUN + 5000);
  assert.equal(d.prestige, 10);
  assert.equal(d.snapshots.length, 10);
  assert.equal(d.level, 25);
});

test("deriving from XP up to a held Legend prestige", () => {
  const d = deriveProgressionFromEntryXP(14 * RUN + 5000, 12);
  assert.equal(d.prestige, 12);
  assert.equal(deriveProgressionFromEntryXP(30 * RUN, 99).prestige, 20);
});

test("P10 and below derive exactly as before", () => {
  assert.equal(deriveProgressionFromEntryXP(3 * RUN + 10).prestige, 3);
  assert.equal(deriveProgressionFromEntryXP(0).prestige, 0);
});

test("rank titles cover the Legend tiers", () => {
  assert.equal(rankTitle(1, 10), "Prestige Master Rookie");
  assert.equal(rankTitle(1, 11), "Obsidian Rookie");
  assert.equal(rankTitle(25, 20), "Eternal Prestige Ready");
});
