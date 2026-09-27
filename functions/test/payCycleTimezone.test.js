// Day boundaries follow each USER's calendar, never the server's (UTC).
// Regression: with UTC boundaries, any recompute after 18:00 Mountain rolled
// the cheque window a day early — friends saw 0h on the cutoff evening while
// the owner's phone (correctly) still showed the closing cheque.
//
// The process TZ is deliberately set to something nobody uses so a missed
// conversion cannot pass by accident.
process.env.TZ = "Pacific/Kiritimati";

const test = require("node:test");
const assert = require("node:assert/strict");
const { currentPayCycle, weeklyStats, currentStreak, workedDayStrings } = require("../src/stats/recompute.js");
const {
  makeCalendar,
  resolveUserTimeZone,
  offsetMinutesFromLocalMidnight,
  timeZoneForOffsetMinutes,
} = require("../src/stats/localCalendar.js");

const edmonton = makeCalendar("America/Edmonton");
const toronto = makeCalendar("America/Toronto");

// Logan/tyhigh settings on 2026-09-26: bi-weekly, cutoff Sept 26 (Mountain
// midnight = 06:00Z), payday Oct 1.
const settings = {
  payPeriodType: "bi-weekly",
  payPeriodUsesCutoff: true,
  nextCutoff: 1790402400000, // 2026-09-26T06:00:00Z
  nextPayday: 1790920800000, // 2026-10-01T06:00:00Z
};
const at = (iso) => new Date(iso);

test("cutoff evening (22:34 Mountain) still belongs to the closing cheque", () => {
  const cycle = currentPayCycle(settings, at("2026-09-27T04:34:00Z"), edmonton);
  assert.equal(cycle.start.toISOString(), "2026-09-13T06:00:00.000Z");
  assert.equal(cycle.end.toISOString(), "2026-09-27T06:00:00.000Z");
});

test("the new cheque starts at the user's local midnight after the cutoff day", () => {
  const cycle = currentPayCycle(settings, at("2026-09-27T06:00:00Z"), edmonton);
  assert.equal(cycle.start.toISOString(), "2026-09-27T06:00:00.000Z");
  assert.equal(cycle.end.toISOString(), "2026-10-11T06:00:00.000Z");
});

test("weekly window is Monday-aligned in the user's zone", () => {
  // Sunday Sept 27 2026 22:00 MDT = Monday 04:00Z. Mountain week: Mon Sept 21 … Sun Sept 27.
  const week = weeklyStats([], at("2026-09-28T04:00:00Z"), edmonton);
  assert.equal(week.weekStart.toISOString(), "2026-09-21T06:00:00.000Z");
  assert.equal(week.weekEnd.toISOString(), "2026-09-28T06:00:00.000Z");
  // Same instant in Toronto is already Monday 00:00 EDT → the new week.
  const east = weeklyStats([], at("2026-09-28T04:00:00Z"), toronto);
  assert.equal(east.weekStart.toISOString(), "2026-09-28T04:00:00.000Z");
});

test("calendar arithmetic survives the DST change (Nov 1 2026, Mountain)", () => {
  const before = edmonton.startOfDay(at("2026-10-31T18:00:00Z")); // Oct 31 00:00 MDT = 06:00Z
  assert.equal(before.toISOString(), "2026-10-31T06:00:00.000Z");
  const twoDaysOn = edmonton.addDays(before, 2); // Nov 2 00:00 MST = 07:00Z (25h day between)
  assert.equal(twoDaysOn.toISOString(), "2026-11-02T07:00:00.000Z");
  assert.equal(edmonton.isoDate(twoDaysOn), "2026-11-02");
  assert.equal(edmonton.dayDiff(twoDaysOn, before), 2);
});

test("streak counts 'today' in the user's zone", () => {
  // Worked Sept 25 and 26 (Mountain midnights). At 23:00 MDT Sept 26 the streak is 2.
  const entries = [
    { date: 1790316000000, start: 0, end: 0 }, // 2026-09-25T06:00Z
    { date: 1790402400000, start: 0, end: 0 }, // 2026-09-26T06:00Z
  ];
  const worked = workedDayStrings(entries, edmonton);
  assert.deepEqual(worked, ["2026-09-25", "2026-09-26"]);
  assert.equal(currentStreak(worked, at("2026-09-27T05:00:00Z"), edmonton), 2);
});

test("offset is derived from a local-midnight instant", () => {
  assert.equal(offsetMinutesFromLocalMidnight(1790402400000), -360); // 06:00Z midnight → UTC−6
  assert.equal(offsetMinutesFromLocalMidnight(Date.UTC(2026, 8, 26, 22)), 120); // 22:00Z → UTC+2
  assert.equal(offsetMinutesFromLocalMidnight(Date.UTC(2026, 8, 26, 2, 30)), -150); // NDT
  assert.equal(offsetMinutesFromLocalMidnight(Date.UTC(2026, 8, 26, 6, 7)), null); // not a midnight
  assert.equal(timeZoneForOffsetMinutes(-360), "Etc/GMT+6");
  assert.equal(timeZoneForOffsetMinutes(120), "Etc/GMT-2");
  assert.equal(timeZoneForOffsetMinutes(0), "Etc/UTC");
  assert.equal(timeZoneForOffsetMinutes(-150), "America/St_Johns");
});

test("resolveUserTimeZone: profile wins, then latest entry, then pay settings, then default", () => {
  assert.deepEqual(
    resolveUserTimeZone({ userData: { timeZone: "America/Toronto" }, entries: [{ date: 1790402400000 }] }),
    { timeZone: "America/Toronto", source: "profile" }
  );
  assert.deepEqual(
    resolveUserTimeZone({ userData: { timeZone: "Not/AZone" }, entries: [{ date: 1790402400000 }] }),
    { timeZone: "Etc/GMT+6", source: "entries" }
  );
  assert.deepEqual(
    resolveUserTimeZone({ entries: [{ date: 1790402400000 }, { date: Date.UTC(2026, 8, 30, 7) }] }),
    { timeZone: "Etc/GMT+7", source: "entries" } // latest entry wins (Pacific)
  );
  assert.deepEqual(
    resolveUserTimeZone({ paySettings: { nextCutoff: 1790402400000 } }),
    { timeZone: "Etc/GMT+6", source: "paySettings" }
  );
  assert.deepEqual(resolveUserTimeZone({}), { timeZone: "America/Edmonton", source: "default" });
});

test("a fixed-offset zone derived from entries yields the same cheque window as the named zone", () => {
  const derived = makeCalendar("Etc/GMT+6");
  const a = currentPayCycle(settings, at("2026-09-27T04:34:00Z"), derived);
  const b = currentPayCycle(settings, at("2026-09-27T04:34:00Z"), edmonton);
  assert.equal(a.start.getTime(), b.start.getTime());
  assert.equal(a.end.getTime(), b.end.getTime());
});
