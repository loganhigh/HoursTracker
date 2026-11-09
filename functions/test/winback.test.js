const test = require("node:test");
const assert = require("node:assert/strict");
const { winbackDecision, winbackMessage, manualNudgeAllowed, typicalGapDays } = require("../src/admin/winback");
const { atRiskInfo, DAY_MS } = require("../src/admin/analytics");

const NOW = Date.UTC(2026, 10, 8, 17);
const quiet = (days, extra = {}) => ({ totalHours: 400, bestStreak: 12, typicalGapDays: null, lastActiveAt: NOW - days * DAY_MS, ...extra });

test("first push at 7 days quiet, not before", () => {
  assert.equal(winbackDecision(quiet(6), null, NOW).send, 0);
  assert.equal(winbackDecision(quiet(7), null, NOW).send, 1);
});

test("second push at 21 days after the first, then silence", () => {
  const row = quiet(21);
  const state = { quietSinceMs: row.lastActiveAt, stage: 1 };
  assert.equal(winbackDecision(quiet(15), { quietSinceMs: quiet(15).lastActiveAt, stage: 1 }, NOW).send, 0);
  assert.equal(winbackDecision(row, state, NOW).send, 2);
  assert.equal(winbackDecision(quiet(40), { quietSinceMs: quiet(40).lastActiveAt, stage: 2 }, NOW).send, 0);
});

test("coming back starts a fresh sequence", () => {
  const row = quiet(8);
  const oldStretch = { quietSinceMs: row.lastActiveAt - 30 * DAY_MS, stage: 2 };
  assert.equal(winbackDecision(row, oldStretch, NOW).send, 1);
});

test("long-gone users are not started", () => {
  assert.equal(winbackDecision(quiet(60), null, NOW).send, 0);
});

test("never-really-active users are skipped", () => {
  assert.equal(winbackDecision(quiet(10, { totalHours: 2, bestStreak: 1 }), null, NOW).send, 0);
});

test("seasonal workers: usual 20-day breaks push the thresholds out", () => {
  const seasonal = (d) => quiet(d, { typicalGapDays: 20 });
  assert.equal(atRiskInfo(seasonal(15), NOW), null);
  assert.equal(winbackDecision(seasonal(22), null, NOW).send, 0);
  assert.equal(winbackDecision(seasonal(24), null, NOW).send, 1);
  const s = seasonal(38);
  assert.equal(winbackDecision(s, { quietSinceMs: s.lastActiveAt, stage: 1 }, NOW).send, 2);
});

test("messages use the user's own numbers", () => {
  assert.match(winbackMessage({ totalHours: 1234.4 }, 1).body, /1,234 hours/);
  assert.match(winbackMessage({ totalHours: 50, bestStreak: 9 }, 2).body, /9-day best streak/);
});

test("manual nudge once a week", () => {
  assert.equal(manualNudgeAllowed(null, NOW), true);
  assert.equal(manualNudgeAllowed({ lastManualMs: NOW - 3 * DAY_MS }, NOW), false);
  assert.equal(manualNudgeAllowed({ lastManualMs: NOW - 8 * DAY_MS }, NOW), true);
});

test("typical gap: daily worker ~1, rotation worker ~long", () => {
  const days = (offsets) => offsets.map((o) => new Date(NOW - o * DAY_MS).toISOString().slice(0, 10)).sort();
  assert.equal(typicalGapDays(days([1, 2, 3, 4, 5, 6, 8, 9, 10, 11]), NOW), 2);
  const rotation = [];
  for (let block = 0; block < 6; block++) for (let d = 0; d < 7; d++) rotation.push(block * 21 + d + 1);
  assert.equal(typicalGapDays(days(rotation), NOW), 15);
  assert.equal(typicalGapDays(days([1, 2, 3]), NOW), null);
});

test("no push until the usual break has been measured", () => {
  const row = quiet(10);
  delete row.typicalGapDays;
  assert.equal(winbackDecision(row, null, NOW).send, 0);
});
