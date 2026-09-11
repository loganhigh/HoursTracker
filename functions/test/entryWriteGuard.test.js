const test = require("node:test");
const assert = require("node:assert/strict");
const { stampToMillis, staleWriteDecision } = require("../src/stats/entryWriteGuard.js");

test("stampToMillis accepts number, Timestamp-like, Date, ISO string; rejects junk", () => {
  assert.equal(stampToMillis(1700000000000), 1700000000000);
  assert.equal(stampToMillis({ toMillis: () => 5 }), 5);
  assert.equal(stampToMillis({ _seconds: 2, _nanoseconds: 5e8 }), 2500);
  assert.equal(stampToMillis(new Date(1000)), 1000);
  assert.equal(stampToMillis("2026-09-11T00:00:00Z"), Date.UTC(2026, 8, 11));
  assert.equal(stampToMillis(null), null);
  assert.equal(stampToMillis(undefined), null);
  assert.equal(stampToMillis("not a date"), null);
  assert.equal(stampToMillis(NaN), null);
});

test("no stored doc or unstamped stored doc → never stale", () => {
  assert.equal(staleWriteDecision(undefined, { modifiedAt: 1 }).stale, false);
  assert.equal(staleWriteDecision(undefined, {}).stale, false);
  assert.equal(staleWriteDecision({ start: 1 }, {}).stale, false);
  assert.equal(staleWriteDecision({ start: 1 }, { modifiedAt: 1 }).stale, false);
});

test("stamped stored doc + unstamped client (pre-guard build) → stale", () => {
  const d = staleWriteDecision({ modifiedAt: 2000 }, { start: 1 });
  assert.equal(d.stale, true);
  assert.equal(d.reason, "unstamped-client");
});

test("client stamp older than stored → stale; equal or newer → accepted", () => {
  assert.deepEqual(
    staleWriteDecision({ modifiedAt: 2000 }, { modifiedAt: 1999 }),
    { stale: true, reason: "older-stamp", existingMs: 2000, payloadMs: 1999 }
  );
  assert.equal(staleWriteDecision({ modifiedAt: 2000 }, { modifiedAt: 2000 }).stale, false);
  assert.equal(staleWriteDecision({ modifiedAt: 2000 }, { modifiedAt: 2001 }).stale, false);
});

test("stored Firestore Timestamp compares against client epoch ms", () => {
  const stored = { modifiedAt: { _seconds: 2, _nanoseconds: 0 } };
  assert.equal(staleWriteDecision(stored, { modifiedAt: 1500 }).stale, true);
  assert.equal(staleWriteDecision(stored, { modifiedAt: 2000 }).stale, false);
});
