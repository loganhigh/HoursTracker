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

const {
  REMINDER_AFTER_MS,
  prestigeReadyMessage,
  prestigeReminderDecision,
} = require("../src/stats/prestigeReady");
const { PRESTIGE_TIER_NAMES } = require("../src/stats/recompute");

test("push copy names the next rank and says tap", () => {
  const first = prestigeReadyMessage(4, 1, PRESTIGE_TIER_NAMES);
  assert.match(first.body, /Tap to Prestige to P5 Diamond/);
  const reminder = prestigeReadyMessage(0, 2, PRESTIGE_TIER_NAMES);
  assert.match(reminder.body, /P1 Bronze/);
  assert.match(reminder.title, /waiting/);
});

test("one reminder after the wait, only while still unprestiged", () => {
  const now = Date.UTC(2026, 10, 10);
  const ev = { prestige: 2, createdAtMs: now - REMINDER_AFTER_MS };
  assert.strictEqual(prestigeReminderDecision(ev, 2, now), "remind");
  assert.strictEqual(prestigeReminderDecision({ ...ev, createdAtMs: now - 1000 }, 2, now), "wait");
  assert.strictEqual(prestigeReminderDecision({ ...ev, remindedAtMs: now }, 2, now), "done");
  assert.strictEqual(prestigeReminderDecision(ev, 3, now), "done");
  assert.strictEqual(prestigeReminderDecision(ev, 1, now), "done");
});
