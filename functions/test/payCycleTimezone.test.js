// The server's day boundaries must follow the users' local calendar, not UTC.
// Every Date-local call in recompute (setHours(0), getDay, new Date(y, m, 1))
// resolves against process.env.TZ, which index.js pins to America/Edmonton.
// Regression: with UTC boundaries, any recompute after 18:00 Mountain rolled
// the cheque window a day early — friends saw 0h on the cutoff evening while
// the owner's phone (correctly) still showed the closing cheque.
process.env.TZ = "America/Edmonton";

const test = require("node:test");
const assert = require("node:assert/strict");
const { currentPayCycle, weeklyStats } = require("../src/stats/recompute.js");

// Logan/tyhigh settings on 2026-09-26: bi-weekly, cutoff Sept 26 (local
// midnight = 06:00Z), payday Oct 1.
const settings = {
  payPeriodType: "bi-weekly",
  payPeriodUsesCutoff: true,
  nextCutoff: 1790402400000, // 2026-09-26T06:00:00Z
  nextPayday: 1790920800000, // 2026-10-01T06:00:00Z
};
const local = (iso) => new Date(iso);

test("cutoff evening (22:34 Mountain) still belongs to the closing cheque", () => {
  const cycle = currentPayCycle(settings, local("2026-09-27T04:34:00Z")); // Sept 26, 22:34 MDT
  assert.equal(cycle.start.toISOString(), "2026-09-13T06:00:00.000Z");
  assert.equal(cycle.end.toISOString(), "2026-09-27T06:00:00.000Z");
});

test("the new cheque starts at local midnight after the cutoff day", () => {
  const cycle = currentPayCycle(settings, local("2026-09-27T06:00:00Z")); // Sept 27, 00:00 MDT
  assert.equal(cycle.start.toISOString(), "2026-09-27T06:00:00.000Z");
  assert.equal(cycle.end.toISOString(), "2026-10-11T06:00:00.000Z");
});

test("weekly window is Monday-aligned in local time", () => {
  // Sunday Sept 27 2026, 22:00 MDT = Monday 04:00Z. Local week: Mon Sept 21 … Sun Sept 27.
  const week = weeklyStats([], local("2026-09-28T04:00:00Z"));
  assert.equal(week.weekStart.toISOString(), "2026-09-21T06:00:00.000Z");
  assert.equal(week.weekEnd.toISOString(), "2026-09-28T06:00:00.000Z");
});
