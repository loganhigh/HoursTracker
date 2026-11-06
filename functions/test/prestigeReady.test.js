const test = require("node:test");
const assert = require("node:assert");
const {
  canPrestigeFromXP,
  buildSnapshotsForPrestige,
  levelStateFromXP,
  MAX_PRESTIGE,
} = require("../src/stats/recompute");

const RUN = 86322; // XP for one full Level 1→25 run

test("finishing level 25 makes prestige available", () => {
  assert.strictEqual(canPrestigeFromXP(RUN, 0, []), true);
  assert.strictEqual(canPrestigeFromXP(RUN + 500, 0, []), true);
});

test("reaching level 25 without finishing it does not", () => {
  assert.strictEqual(levelStateFromXP(RUN - 1, 0, []), 25);
  assert.strictEqual(canPrestigeFromXP(RUN - 1, 0, []), false);
  assert.strictEqual(canPrestigeFromXP(0, 0, []), false);
});

test("later prestige runs deduct earlier runs via snapshots", () => {
  const snaps = buildSnapshotsForPrestige(2);
  assert.strictEqual(canPrestigeFromXP(3 * RUN - 1, 2, snaps), false);
  assert.strictEqual(canPrestigeFromXP(3 * RUN, 2, snaps), true);
  assert.strictEqual(canPrestigeFromXP(3 * RUN, 2, []), true);
});

test("never offered at the prestige cap", () => {
  assert.strictEqual(canPrestigeFromXP(RUN * (MAX_PRESTIGE + 2), MAX_PRESTIGE, []), false);
});
