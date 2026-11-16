"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { appreciationStatus, appreciationMessage, APPRECIATION_COOLDOWN_MS } = require("../src/admin/appreciation");

const DAY = 86_400_000;
const NOW = Date.UTC(2026, 10, 16);
const active = { lastActiveAt: NOW - DAY };

test("first thank-you is allowed for an active user", () => {
  assert.deepEqual(appreciationStatus(null, active, NOW), { allowed: true, reason: "ok", nextAllowedMs: null });
});

test("one per 90 days", () => {
  assert.equal(APPRECIATION_COOLDOWN_MS, 90 * DAY);
  const s = appreciationStatus({ lastThanksMs: NOW - 30 * DAY }, active, NOW);
  assert.equal(s.allowed, false);
  assert.equal(s.reason, "cooldown");
  assert.equal(s.nextAllowedMs, NOW + 60 * DAY);
  assert.equal(appreciationStatus({ lastThanksMs: NOW - 91 * DAY }, active, NOW).allowed, true);
});

test("only while still active", () => {
  assert.equal(appreciationStatus(null, { lastActiveAt: NOW - 10 * DAY }, NOW).reason, "inactive");
  assert.equal(appreciationStatus(null, { lastShiftMs: NOW - 2 * DAY }, NOW).allowed, true);
  assert.equal(appreciationStatus(null, {}, NOW).allowed, false);
});

test("copy uses their name and hours", () => {
  const m = appreciationMessage({ displayName: "jade", totalHours: 1234.4 });
  assert.equal(m.title, "Thank you, jade");
  assert.match(m.body, /1,234 hours/);
  assert.equal(appreciationMessage({}).title, "Thank you for tracking with us");
});
