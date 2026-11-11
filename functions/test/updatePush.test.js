const test = require("node:test");
const assert = require("node:assert/strict");
const { isVersionOlder, needsUpdatePush, updatePushMessage } = require("../src/admin/updatePush");

test("version compare is numeric, not alphabetical", () => {
  assert.equal(isVersionOlder("3.4", "3.10"), true);
  assert.equal(isVersionOlder("3.10", "3.4"), false);
  assert.equal(isVersionOlder("3.8", "3.8"), false);
  assert.equal(isVersionOlder("3.8", "3.8.0"), false);
  assert.equal(isVersionOlder("3.7.9", "3.8"), true);
});

test("only out-of-date or unknown versions get the push", () => {
  assert.equal(needsUpdatePush({ appVersion: "3.7" }, "3.8"), true);
  assert.equal(needsUpdatePush({ appVersion: "3.8" }, "3.8"), false);
  assert.equal(needsUpdatePush({ appVersion: "3.9" }, "3.8"), false);
  assert.equal(needsUpdatePush({}, "3.8"), true);
});

test("message names the version", () => {
  const m = updatePushMessage("3.8");
  assert.equal(m.title, "New Update!");
  assert.match(m.body, /Version 3\.8/);
});
