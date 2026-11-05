const test = require("node:test");
const assert = require("node:assert");
const chat = require("../src/social/chat");

test("ordinary encouragement passes the filter", () => {
  for (const text of [
    "Great week @logan, keep it up!",
    "Thanks for the support everyone",
    "Class assignment done, back to work",
    "That shift was hell but we made it",
  ]) {
    assert.strictEqual(chat.messageProblem(text), null, text);
  }
});

test("slurs, sexual content and self-harm taunts are refused", () => {
  for (const text of ["you're a f4ggot", "FUUUCK this", "kill yourself", "send nudes", "what a b!tch"]) {
    assert.ok(chat.messageProblem(text), text);
  }
});

test("empty and overlong messages are refused", () => {
  assert.ok(chat.messageProblem(""));
  assert.ok(chat.messageProblem("a".repeat(chat.MESSAGE_MAX + 1)));
  assert.strictEqual(chat.messageProblem("a".repeat(chat.MESSAGE_MAX)), null);
});

test("mentions are unique, lowercased, capped and ignore emails", () => {
  assert.deepStrictEqual(chat.extractMentions("Nice @Logan and @jacob_2, @logan again"), ["logan", "jacob_2"]);
  assert.deepStrictEqual(chat.extractMentions("mail me at bob@example.com"), []);
  assert.deepStrictEqual(chat.extractMentions("@ab too short, @1abc starts with digit"), []);
  const many = Array.from({ length: 8 }, (_, i) => `@user${i}`).join(" ");
  assert.strictEqual(chat.extractMentions(many).length, chat.MAX_MENTIONS);
});

test("a thread id is the same whoever writes first", () => {
  assert.strictEqual(chat.directThreadId("b", "a"), chat.directThreadId("a", "b"));
});

test("cleanMessage trims and collapses blank lines", () => {
  assert.strictEqual(chat.cleanMessage("  hi\r\n\n\n\nthere  "), "hi\n\nthere");
});
