const test = require("node:test");
const assert = require("node:assert/strict");
const { stripEmoji, sanitizeDisplayName } = require("../src/stats/recompute.js");

test("stripEmoji removes emoji, flags, ZWJ sequences and skin tones", () => {
  assert.equal(stripEmoji("Jake 🔥"), "Jake");
  assert.equal(stripEmoji("👨‍👩‍👧 LG. 🇵🇭"), "LG.");
  assert.equal(stripEmoji("Al 👍🏽 B"), "Al B");
  assert.equal(stripEmoji("🔥🔥"), "");
});

test("stripEmoji keeps ordinary text and digits", () => {
  assert.equal(stripEmoji("Bob #1"), "Bob #1");
  assert.equal(stripEmoji("  spaced   out  "), "spaced out");
});

test("sanitizeDisplayName falls back when only emoji remain", () => {
  assert.equal(sanitizeDisplayName("🔥", "Friend"), "Friend");
  assert.equal(sanitizeDisplayName("Holly ✨", "Friend"), "Holly");
});
