"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  BOARD_INACTIVE_MS,
  lastActivityMs,
  isInactiveForBoard,
  withoutUids,
} = require("../src/leaderboard/boardActivity");

const DAY = 86_400_000;
const NOW = Date.UTC(2026, 10, 15);

test("latest signal wins", () => {
  const ts = { toMillis: () => NOW - 2 * DAY };
  assert.equal(lastActivityMs({ presenceMs: NOW - 40 * DAY, lastShiftMs: NOW - 5 * DAY }), NOW - 5 * DAY);
  assert.equal(lastActivityMs({ presenceMs: ts, lastShiftMs: 0 }), NOW - 2 * DAY);
  assert.equal(lastActivityMs({ profileLastShift: ts }), NOW - 2 * DAY);
  assert.equal(lastActivityMs({}), 0);
});

test("30-day cutoff", () => {
  assert.equal(BOARD_INACTIVE_MS, 30 * DAY);
  assert.equal(isInactiveForBoard(NOW - 29 * DAY, NOW), false);
  assert.equal(isInactiveForBoard(NOW - 30 * DAY, NOW), false);
  assert.equal(isInactiveForBoard(NOW - 31 * DAY, NOW), true);
});

test("no signal keeps the user on the board", () => {
  assert.equal(isInactiveForBoard(0, NOW), false);
  assert.equal(isInactiveForBoard(null, NOW), false);
});

test("returning user is active again", () => {
  const activity = lastActivityMs({ presenceMs: NOW - 60_000, lastShiftMs: NOW - 90 * DAY });
  assert.equal(isInactiveForBoard(activity, NOW), false);
});

test("withoutUids re-ranks the previous board", () => {
  const rows = [{ uid: "a", rank: 1 }, { uid: "b", rank: 2 }, { uid: "c", rank: 3 }];
  assert.deepEqual(withoutUids(rows, new Set(["a"])), [{ uid: "b", rank: 1 }, { uid: "c", rank: 2 }]);
  assert.equal(withoutUids(rows, new Set()), rows);
  assert.deepEqual(withoutUids(null, new Set(["a"])), []);
});
