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

test("board chat alert mode defaults to mentions", () => {
  assert.equal(chat.boardChatAlertMode(undefined), "mentions");
  assert.equal(chat.boardChatAlertMode({}), "mentions");
  assert.equal(chat.boardChatAlertMode({ boardChatAlerts: "bogus" }), "mentions");
  assert.equal(chat.boardChatAlertMode({ boardChatAlerts: "off" }), "off");
  assert.equal(chat.boardChatAlertMode({ boardChatAlerts: "all" }), "all");
});

test("board chat digest is throttled and skips active readers", () => {
  const now = 1_800_000_000_000;
  assert.equal(chat.shouldSendDigest({ nowMs: now }), true);
  assert.equal(chat.shouldSendDigest({ lastDigestAt: now - 10 * 60e3, nowMs: now }), false);
  assert.equal(chat.shouldSendDigest({ lastDigestAt: now - 31 * 60e3, nowMs: now }), true);
  assert.equal(chat.shouldSendDigest({ lastReadAt: now - 60e3, nowMs: now }), false);
  assert.equal(chat.shouldSendDigest({ lastReadAt: { toMillis: () => now - 10 * 60e3 }, nowMs: now }), true);
});

test("board chat digest title", () => {
  assert.equal(chat.digestTitle(1), "New message in Board Chat");
  assert.equal(chat.digestTitle(5), "5 new messages in Board Chat");
  assert.equal(chat.digestTitle(250), "99+ new messages in Board Chat");
});
