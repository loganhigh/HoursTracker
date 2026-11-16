const test = require("node:test");
const assert = require("node:assert/strict");
const aa = require("../src/admin/analytics");

const NOW = Date.UTC(2026, 7, 20, 18, 0, 0); // fixed clock
const DAY = aa.DAY_MS;

test("recency beats lifetime: active newcomer outranks dormant veteran", () => {
  const veteran = {
    totalHours: 2000, bestStreak: 40,
    lastActiveAt: NOW - 30 * DAY, lastShiftMs: NOW - 30 * DAY,
    weeklyShifts: 0, weeklyHours: 0, currentStreak: 0,
  };
  const newcomer = {
    totalHours: 60, bestStreak: 4,
    lastActiveAt: NOW - 3600 * 1000, lastShiftMs: NOW - 3600 * 1000,
    weeklyShifts: 5, weeklyHours: 42, currentStreak: 6,
  };
  assert.ok(aa.activityScore(newcomer, NOW) > aa.activityScore(veteran, NOW));
  assert.equal(aa.activityScore(veteran, NOW), 0); // fully dormant scores zero
});

test("score is bounded 0..100 and full engagement approaches the top", () => {
  const maxed = {
    lastActiveAt: NOW, lastShiftMs: NOW,
    weeklyShifts: 9, weeklyHours: 60, currentStreak: 14,
  };
  const score = aa.activityScore(maxed, NOW);
  assert.ok(score >= 95 && score <= 100);
});

test("at-risk requires prior activity and 3+ quiet days", () => {
  // Never really used the app — nothing to lose, not at risk.
  assert.equal(aa.atRiskInfo({ totalHours: 2, bestStreak: 1, lastActiveAt: NOW - 10 * DAY }, NOW), null);
  // Active yesterday — not at risk.
  assert.equal(aa.atRiskInfo({ totalHours: 100, lastActiveAt: NOW - 1 * DAY }, NOW), null);

  const fading = aa.atRiskInfo({
    totalHours: 300, bestStreak: 12, currentStreak: 0,
    weeklyShifts: 0, lastActiveAt: NOW - 8 * DAY, lastShiftMs: NOW - 9 * DAY,
  }, NOW);
  assert.equal(fading.inactiveDays, 8);
  assert.ok(fading.reasons.some((r) => r.includes("8 days")));
  assert.ok(fading.reasons.some((r) => r.includes("12-day best streak ended")));
  assert.ok(fading.reasons.some((r) => r.includes("0 shifts this week")));
});

test("signup buckets land on the right days and ignore out-of-range", () => {
  const times = [
    NOW - 1000,            // today
    NOW - 1 * DAY,         // yesterday
    NOW - 1 * DAY - 5000,  // yesterday again
    NOW - 200 * DAY,       // far out of range
  ];
  const buckets = aa.signupBuckets(times, 7, NOW);
  assert.equal(buckets.length, 7);
  assert.equal(buckets[6].count, 1); // today
  assert.equal(buckets[5].count, 2); // yesterday
  assert.equal(buckets.reduce((s, b) => s + b.count, 0), 3);
});

test("countWithin respects the window", () => {
  const rows = [
    { lastActiveAt: NOW - 1000 },
    { lastActiveAt: NOW - 6 * DAY },
    { lastActiveAt: NOW - 20 * DAY },
    { lastActiveAt: null },
  ];
  assert.equal(aa.countWithin(rows, "lastActiveAt", 1, NOW), 1);
  assert.equal(aa.countWithin(rows, "lastActiveAt", 7, NOW), 2);
  assert.equal(aa.countWithin(rows, "lastActiveAt", 30, NOW), 3);
});

// --- Activity breakdown + week-one cohorts -------------------------------

{
  const { activityBucket, weekOneCohorts, startOfUTCWeek } = require("../src/admin/analytics");
  const D = 86_400_000;
  const N = Date.UTC(2026, 10, 15, 12); // Sun 15 Nov 2026

  test("activityBucket sorts users into active / quiet / gone / never", () => {
    assert.equal(activityBucket({ totalHours: 0, lastActiveAt: N - D }, N), "never");
    assert.equal(activityBucket({ realHours: 5, lastActiveAt: N - 2 * D }, N), "active");
    assert.equal(activityBucket({ realHours: 5, lastActiveAt: N - 12 * D }, N), "quiet");
    assert.equal(activityBucket({ realHours: 5, lastActiveAt: N - 45 * D }, N), "gone");
    // A recent shift counts even without a presence stamp.
    assert.equal(activityBucket({ realHours: 5, lastShiftMs: N - D }, N), "active");
  });

  test("startOfUTCWeek is Monday", () => {
    assert.equal(new Date(startOfUTCWeek(N)).getUTCDay(), 1);
    assert.equal(startOfUTCWeek(N), Date.UTC(2026, 10, 9));
  });

  test("weekOneCohorts counts distinct log days in the first week", () => {
    const created = Date.UTC(2026, 9, 26, 9); // Mon of cohort 3 weeks ago
    const users = [
      { createdAt: created, shiftDatesMs: [created, created + D, created + 3 * D], lastTouchMs: N - D },
      { createdAt: created, shiftDatesMs: [created, created + 2 * 3600_000, created + 9 * D], lastTouchMs: 0 },
      { createdAt: created + D, shiftDatesMs: [], lastTouchMs: 0 },
    ];
    const cohorts = weekOneCohorts(users, N, 4);
    const c = cohorts.find((x) => x.weekStartMs === Date.UTC(2026, 9, 26));
    assert.equal(c.signups, 3);
    assert.equal(c.loggedAny, 2);
    assert.equal(c.hitGoal, 1);
    assert.equal(c.activeNow, 1);
    assert.equal(c.complete, true);
    assert.equal(cohorts[cohorts.length - 1].complete, false);
  });
}
