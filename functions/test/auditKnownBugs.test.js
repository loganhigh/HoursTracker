// Known bugs found in the 2026-10-31 audit. Each test asserts the CORRECT
// behaviour and is marked `todo`, so it runs and reports without failing the
// suite. When a fix lands, the test starts passing — drop the `todo` then.
process.env.TZ = "Pacific/Kiritimati";

const test = require("node:test");
const assert = require("node:assert/strict");
const { weeklyStats, buildBoardEntries } = require("../src/stats/recompute.js");
const { makeCalendar } = require("../src/stats/localCalendar.js");

const edmonton = makeCalendar("America/Edmonton");
const H = 3600000;
const shift = (iso) => {
  const day = Date.parse(iso);
  return { date: day, start: day + 8 * H, end: day + 16 * H, breakMinutes: 0 };
};

test("server week honours the user's 'Week starts on' setting (Home uses it)", { todo: "weeklyStats is always Monday-aligned" }, () => {
  // Sunday-start user: Sun Oct 25 + Mon Oct 26, checked Wed Oct 28.
  // Home shows 16h; friends see the server's 8h.
  const entries = [shift("2026-10-25T06:00:00Z"), shift("2026-10-26T06:00:00Z")];
  const settings = { weekStartWeekday: 1 };
  const week = weeklyStats(entries, new Date("2026-10-28T18:00:00Z"), edmonton, settings);
  assert.equal(week.hours, 16);
});

test("rows with no public profile (deleted accounts) are not ranked", { todo: "purge leaves boardHours; board ranks it as 'Tracker'" }, () => {
  const rows = buildBoardEntries(
    [{ uid: "deleted", hours: 900 }, { uid: "live", hours: 10 }],
    new Map([["live", { username: "amy" }]])
  );
  assert.deepEqual(rows.map((r) => r.uid), ["live"]);
});
