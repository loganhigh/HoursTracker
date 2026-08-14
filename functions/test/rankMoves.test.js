const test = require("node:test");
const assert = require("node:assert/strict");
const rm = require("../src/leaderboard/rankMoves");

const MIN = 60 * 1000;
const THROTTLE = 6 * 60 * MIN;
const TTL = 24 * 60 * MIN;
const NOW = 1_000_000_000_000; // fixed clock; Date.now is never used in the module

function board(rows) {
  return rows.map(([uid, hours], i) => ({ uid, name: uid, hours, rank: i + 1 }));
}

function candidatesFor({ previous, current, state = {}, now = NOW }) {
  return rm.computeCandidates({ previous, current, state, now, offBoardTtlMs: TTL });
}

// --- Initial load / no-op refreshes ----------------------------------------

test("identical boards produce no candidates", () => {
  const b = board([["a", 700], ["b", 650], ["c", 600]]);
  const { candidates } = candidatesFor({ previous: b, current: b });
  assert.equal(candidates.length, 0);
});

test("hours change without rank change is not a move", () => {
  const prev = board([["a", 700], ["b", 650]]);
  const cur = board([["a", 700], ["b", 660]]); // b gained hours, same order
  const { candidates } = candidatesFor({ previous: prev, current: cur });
  assert.equal(candidates.length, 0);
});

test("tied hours keep deterministic input order and never oscillate", () => {
  // The board is built from a query ordered (hours desc, uid asc); equal hours
  // arrive in the same order every time, so the diff must be empty.
  const b = board([["a", 670.4], ["b", 670.4]]);
  const { candidates } = candidatesFor({ previous: b, current: b });
  assert.equal(candidates.length, 0);
});

// --- Single overtake --------------------------------------------------------

test("single overtake: symmetric candidates, correct attribution", () => {
  const prev = board([["joey", 670.4], ["ethan", 659]]);
  const cur = board([["ethan", 675], ["joey", 670.4]]);
  const { candidates, prevRankByUid } = candidatesFor({ previous: prev, current: cur });

  const ethan = candidates.find((c) => c.uid === "ethan");
  const joey = candidates.find((c) => c.uid === "joey");
  assert.deepEqual({ delta: ethan.delta, from: ethan.baselineRank, to: ethan.rank }, { delta: 1, from: 2, to: 1 });
  assert.deepEqual({ delta: joey.delta, from: joey.baselineRank, to: joey.rank }, { delta: -1, from: 1, to: 2 });

  const overtaker = rm.nearestOvertaker(joey, cur, prevRankByUid);
  assert.equal(overtaker.uid, "ethan");
  const passed = rm.passedUsers(ethan, cur, prevRankByUid);
  assert.deepEqual(passed.map((p) => p.uid), ["joey"]);
});

test("overtake event has deterministic id and competitive type", () => {
  const prev = board([["joey", 670], ["ethan", 659]]);
  const cur = board([["ethan", 675], ["joey", 670]]);
  const { candidates, prevRankByUid } = candidatesFor({ previous: prev, current: cur });
  const joey = candidates.find((c) => c.uid === "joey");
  const overtaker = rm.nearestOvertaker(joey, cur, prevRankByUid);
  const ev1 = rm.buildEvent({ cand: joey, overtaker, passed: [], milestone: null, nowMs: NOW });
  const ev2 = rm.buildEvent({ cand: joey, overtaker, passed: [], milestone: null, nowMs: NOW + 5 });
  assert.equal(ev1.id, ev2.id); // retry-safe
  assert.equal(ev1.type, "overtaken");
  assert.equal(ev1.overtakerUid, "ethan");
});

// --- Removal vs overtake ----------------------------------------------------

test("deletion above is an adjustment, never a false pass", () => {
  const prev = board([["gone", 800], ["a", 700], ["b", 650]]);
  const cur = board([["a", 700], ["b", 650]]); // "gone" deleted; a,b move up
  const { candidates, prevRankByUid } = candidatesFor({ previous: prev, current: cur });
  const a = candidates.find((c) => c.uid === "a");
  assert.equal(a.delta, 1);
  const passed = rm.passedUsers(a, cur, prevRankByUid);
  assert.equal(passed.length, 0); // nobody was competitively passed
  const ev = rm.buildEvent({ cand: a, overtaker: null, passed, milestone: null, nowMs: NOW });
  assert.equal(ev.type, "adjustment");
});

test("rank drop with nobody coming past uses neutral wording", () => {
  const note = rm.composeNotification({ rank: 7, delta: -1, overtakerName: null, milestone: null });
  assert.ok(!note.body.includes("passed"));
});

// --- Multi-position jump / consolidation -----------------------------------

test("multi-position jump is one candidate with the full delta", () => {
  const prev = board([["a", 900], ["b", 850], ["c", 800], ["d", 750], ["e", 500]]);
  const cur = board([["a", 900], ["e", 880], ["b", 850], ["c", 800], ["d", 750]]);
  const { candidates, prevRankByUid } = candidatesFor({ previous: prev, current: cur });
  const e = candidates.find((c) => c.uid === "e");
  assert.deepEqual({ delta: e.delta, to: e.rank }, { delta: 3, to: 2 });
  const passed = rm.passedUsers(e, cur, prevRankByUid);
  assert.deepEqual(passed.map((p) => p.uid).sort(), ["b", "c", "d"]);
  const note = rm.composeNotification({ rank: 2, delta: 3, overtakerName: null, milestone: null });
  assert.ok(note.body.includes("3 spots"));
});

test("baseline persists across refreshes so drift coalesces into one send", () => {
  // Refresh 1: user climbs 10 -> 9 while ACTIVE (pended, baseline stays 10).
  const entryAfterPend = rm.decideCandidate({
    cand: { uid: "u", rank: 9, delta: 1, baselineRank: 10 },
    entry: { rank: 10, at: 0 },
    now: NOW,
    lastActiveMs: NOW - MIN, // active
    alertsEnabled: true,
    throttleMs: THROTTLE,
    overtaker: null,
    milestone: null,
  });
  assert.equal(entryAfterPend.action, "pend");
  assert.equal(entryAfterPend.entry.rank, 10); // baseline NOT advanced

  // Refresh 2: state baseline 10, now at rank 6 -> candidate delta is 4.
  const state = { u: entryAfterPend.entry };
  const prev = board([["a", 9], ["b", 8], ["c", 7], ["d", 6], ["e", 5], ["u", 1]]);
  const cur = board([["a", 9], ["b", 8], ["c", 7], ["d", 6], ["e", 5], ["u", 4]]);
  void prev; void cur;
  const { candidates } = candidatesFor({
    previous: board([["x", 100]]),
    current: [{ uid: "u", name: "u", rank: 6 }],
    state,
  });
  const u = candidates.find((c) => c.uid === "u");
  assert.deepEqual({ delta: u.delta, from: u.baselineRank }, { delta: 4, from: 10 });
});

// --- Five-minute inactivity gate -------------------------------------------

test("active user is pended, not pushed", () => {
  const v = rm.decideCandidate({
    cand: { uid: "u", rank: 4, delta: 1, baselineRank: 5 },
    entry: { rank: 5, at: 0 },
    now: NOW,
    lastActiveMs: NOW - 2 * MIN,
    alertsEnabled: true,
    throttleMs: THROTTLE,
    overtaker: null,
    milestone: null,
  });
  assert.equal(v.action, "pend");
  assert.equal(v.entry.pending.rank, 4);
});

test("user already inactive 30 minutes is sent promptly", () => {
  const v = rm.decideCandidate({
    cand: { uid: "u", rank: 4, delta: 1, baselineRank: 5 },
    entry: { rank: 5, at: 0 },
    now: NOW,
    lastActiveMs: NOW - 30 * MIN,
    alertsEnabled: true,
    throttleMs: THROTTLE,
    overtaker: null,
    milestone: null,
  });
  assert.equal(v.action, "send");
  assert.equal(v.entry.rank, 4); // baseline advanced on send
  assert.equal(v.entry.pending, undefined);
});

test("flush holds while user is back in the app", () => {
  const v = rm.resolvePending({
    entry: { rank: 5, at: 0, pending: { rank: 4, delta: 1, baselineRank: 5, since: NOW - 10 * MIN } },
    now: NOW,
    lastActiveMs: NOW - 3 * MIN, // returned after 3 minutes
    currentRank: 4,
    alertsEnabled: true,
  });
  assert.equal(v.action, "hold");
  assert.ok(v.entry.pending);
});

test("flush sends after 5+ minutes away, at the LATEST rank", () => {
  const v = rm.resolvePending({
    entry: { rank: 10, at: 0, pending: { rank: 9, delta: 1, baselineRank: 10, since: NOW - 20 * MIN } },
    now: NOW,
    lastActiveMs: NOW - 6 * MIN,
    currentRank: 6, // kept climbing since the pend
    alertsEnabled: true,
  });
  assert.equal(v.action, "send");
  assert.equal(v.entry.rank, 6);
  assert.ok(v.notification.body.includes("4 spots")); // 10 -> 6, consolidated
  assert.ok(v.notification.body.includes("#6"));
});

test("flush drops a move that netted out to zero", () => {
  const v = rm.resolvePending({
    entry: { rank: 10, at: 0, pending: { rank: 8, delta: 2, baselineRank: 10, since: NOW - 20 * MIN } },
    now: NOW,
    lastActiveMs: NOW - 10 * MIN,
    currentRank: 10, // back where they started
    alertsEnabled: true,
  });
  assert.equal(v.action, "clear");
  assert.equal(v.entry.pending, undefined);
});

// --- Dedup / throttle -------------------------------------------------------

test("throttle window suppresses a second send", () => {
  const v = rm.decideCandidate({
    cand: { uid: "u", rank: 3, delta: 1, baselineRank: 4 },
    entry: { rank: 4, at: NOW - MIN }, // notified a minute ago
    now: NOW,
    lastActiveMs: null,
    alertsEnabled: true,
    throttleMs: THROTTLE,
    overtaker: null,
    milestone: null,
  });
  assert.equal(v.action, "skip");
});

test("opt-out advances the baseline so opting back in stays quiet", () => {
  const v = rm.decideCandidate({
    cand: { uid: "u", rank: 3, delta: 2, baselineRank: 5 },
    entry: { rank: 5, at: 0, pending: { rank: 4 } },
    now: NOW,
    lastActiveMs: null,
    alertsEnabled: false,
    throttleMs: THROTTLE,
    overtaker: null,
    milestone: null,
  });
  assert.equal(v.action, "skip");
  assert.equal(v.entry.rank, 3);
  assert.equal(v.entry.pending, undefined);
});

// --- Milestones -------------------------------------------------------------

test("milestones award once, best-ever, never re-award", () => {
  assert.equal(rm.milestoneCrossed(undefined, 60), 100);
  assert.equal(rm.milestoneCrossed(100, 9), 10);
  assert.equal(rm.milestoneCrossed(10, 12), null); // fell out, climbed back: no re-award
  assert.equal(rm.milestoneCrossed(10, 9), null);  // already awarded Top 10
  assert.equal(rm.milestoneCrossed(3, 1), 1);
});

test("reaching #1 gets the special notification", () => {
  const note = rm.composeNotification({ rank: 1, delta: 2, overtakerName: null, milestone: 1 });
  assert.ok(note.title.includes("#1"));
});
