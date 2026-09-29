const test = require("node:test");
const assert = require("node:assert/strict");
const { sanitizeBadgeSummaries, workedDayFacts } = require("../src/stats/badgeSanity.js");

const badge = (name) => ({ name, icon: "x", detail: "", isLegend: false, order: 1 });
const iso = (n) => new Date(Date.UTC(2026, 0, 1) + n * 86400000).toISOString().slice(0, 10);
/** `count` consecutive days starting `offset` days after 2026-01-01 (a Thursday). */
const run = (offset, count) => Array.from({ length: count }, (_, i) => iso(offset + i));

test("streak badges beyond the real best streak are dropped, earned ones kept", () => {
  // mrdiesel, 2026-09-28: real best streak 16, old build published up to 180.
  const published = [
    "14-Day Streak", "21-Day Streak", "30 Days Straight Worked", "60 Days Straight Worked",
    "100 Days Straight Worked", "6-Month Streak", "No Days Off",
  ].map(badge);
  const { badges, dropped } = sanitizeBadgeSummaries(published, {
    workedDayStrings: run(0, 16), bestStreak: 16, workedShiftCount: 16,
  });
  assert.deepEqual(badges.map((b) => b.name), ["14-Day Streak", "No Days Off"]);
  assert.equal(dropped.length, 5);
});

test("badges without a rule always pass through, in order", () => {
  const published = ["1,000 Hours", "Overtime King", "Some Future Badge", "14h Shift"].map(badge);
  const { badges, dropped } = sanitizeBadgeSummaries(published, {
    workedDayStrings: [], bestStreak: 0, workedShiftCount: 0,
  });
  assert.deepEqual(badges, published);
  assert.deepEqual(dropped, []);
});

test("perfect week needs a full Sunday-to-Saturday week", () => {
  // 2026-01-04 is a Sunday. Seven days from Sunday is a perfect week…
  assert.equal(workedDayFacts({ workedDayStrings: run(3, 7), bestStreak: 7 }).perfectWeek, true);
  // …seven days from Thursday straddles two weeks and is not.
  assert.equal(workedDayFacts({ workedDayStrings: run(0, 7), bestStreak: 7 }).perfectWeek, false);
});

test("perfect month and every-weekend month", () => {
  const february = run(31, 28); // all of Feb 2026
  const facts = workedDayFacts({ workedDayStrings: february, bestStreak: 28 });
  assert.equal(facts.perfectMonth, true);
  assert.equal(facts.everyWeekendMonth, true);

  const weekdaysOnly = february.filter((d) => ![0, 6].includes(new Date(d + "T00:00:00Z").getUTCDay()));
  const partial = workedDayFacts({ workedDayStrings: weekdaysOnly, bestStreak: 5 });
  assert.equal(partial.perfectMonth, false);
  assert.equal(partial.everyWeekendMonth, false);

  const { dropped } = sanitizeBadgeSummaries(
    ["Perfect Month", "Every Weekend Worked (Month)", "Perfect Week"].map(badge),
    { workedDayStrings: weekdaysOnly, bestStreak: 5, workedShiftCount: 20 }
  );
  assert.equal(dropped.length, 3);
});

test("weekend and shift-count badges use worked days and worked shifts", () => {
  const days = run(0, 30); // Jan 2026: 5 Saturdays (3,10,17,24,31 → 4 in first 30 days), Sundays 4
  const facts = workedDayFacts({ workedDayStrings: days, bestStreak: 30, workedShiftCount: 30 });
  assert.equal(facts.saturdays, 4);
  assert.equal(facts.sundays, 4);
  const { badges } = sanitizeBadgeSummaries(
    ["Weekend Starter", "Saturday Grinder", "Sunday Warrior", "25 Shifts Logged", "200 Shifts Logged"].map(badge),
    { workedDayStrings: days, bestStreak: 30, workedShiftCount: 30 }
  );
  assert.deepEqual(badges.map((b) => b.name), ["Weekend Starter", "25 Shifts Logged"]);
});

test("empty or malformed input is safe", () => {
  assert.deepEqual(sanitizeBadgeSummaries(undefined, {}), { badges: [], dropped: [] });
  assert.deepEqual(sanitizeBadgeSummaries([], undefined), { badges: [], dropped: [] });
  const odd = [{ icon: "x" }, null, badge("30-Day Streak")];
  const { badges, dropped } = sanitizeBadgeSummaries(odd, {});
  assert.equal(badges.length, 2);
  assert.deepEqual(dropped, ["30-Day Streak"]);
});
