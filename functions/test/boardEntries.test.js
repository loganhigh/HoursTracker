const test = require("node:test");
const assert = require("node:assert/strict");
const { buildBoardEntries } = require("../src/stats/recompute");

test("everyone is ranked by real hours; hidden hours never leave the server", () => {
  const rows = [
    { uid: "a", hours: 120, hidden: false },
    { uid: "b", hours: 300, hidden: true },
    { uid: "c", hours: 200, hidden: false },
    { uid: "z", hours: 0, hidden: false },
  ];
  const profiles = new Map([
    ["a", { username: "amy", currentStreak: 3 }],
    ["b", { displayName: "Ben Smith", currentStreak: 9, countryCode: "ca" }],
    ["c", { username: "cal", hasReviewedApp: true, isSupporter: true }],
  ]);
  const board = buildBoardEntries(rows, profiles);
  assert.deepEqual(board.map((e) => [e.uid, e.rank]), [["b", 1], ["c", 2], ["a", 3]]);
  const ben = board[0];
  assert.equal(ben.hoursHidden, true);
  assert.equal(ben.hours, 0);
  assert.equal(ben.streak, 0);
  assert.equal(ben.name, "Ben");
  assert.equal(ben.countryCode, "CA");
  assert.equal(board[1].hours, 200);
  assert.equal(board[1].isSupporter, true);
  assert.equal(board[2].name, "amy");
});

test("ties break by uid so the order is stable", () => {
  const board = buildBoardEntries(
    [{ uid: "y", hours: 10 }, { uid: "x", hours: 10 }],
    new Map()
  );
  assert.deepEqual(board.map((e) => e.uid), ["x", "y"]);
});
