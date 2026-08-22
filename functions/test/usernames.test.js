const test = require("node:test");
const assert = require("node:assert/strict");
const { normalizeUsername, usernameProblem } = require("../src/social/usernames");

test("normalize trims, lowercases and drops a leading @", () => {
  assert.equal(normalizeUsername("  @Mike_47 "), "mike_47");
  assert.equal(normalizeUsername("@@logan"), "logan");
  assert.equal(normalizeUsername(null), "");
});

test("accepts well-formed handles", () => {
  for (const ok of ["abc", "mike_47", "logan", "a1_", "x".repeat(20)]) {
    assert.equal(usernameProblem(ok), null, ok);
  }
});

test("rejects length, charset and leading-digit problems with a reason", () => {
  assert.match(usernameProblem(""), /Choose/);
  assert.match(usernameProblem("ab"), /at least 3/);
  assert.match(usernameProblem("x".repeat(21)), /at most 20/);
  assert.match(usernameProblem("47mike"), /start with a letter/);
  assert.match(usernameProblem("_mike"), /start with a letter/);
  assert.match(usernameProblem("mike-47"), /letters, numbers, and underscores/);
  assert.match(usernameProblem("mike 47"), /letters, numbers, and underscores/);
  assert.ok(usernameProblem("Mike"), "non-canonical input is never accepted — callers normalize first");
});

test("reserved and moderated handles are refused", () => {
  assert.match(usernameProblem("admin"), /reserved/);
  assert.match(usernameProblem("hourtracker"), /reserved/);
  assert.match(usernameProblem("support"), /reserved/);
  assert.match(usernameProblem("fine_name", () => true), /isn't allowed/);
  assert.equal(usernameProblem("fine_name", () => false), null);
});
