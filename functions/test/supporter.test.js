const test = require("node:test");
const assert = require("node:assert");
const { supporterInfo, withSupporterBadge } = require("../src/supporter");

test("non-supporter gets nothing", () => {
  const s = supporterInfo({ tipTotal: 50, supporterColor: "rose" });
  assert.equal(s.isSupporter, false);
  assert.equal(s.color, "blue");
});

test("small tip: blue only, choice ignored", () => {
  const s = supporterInfo({ isSupporter: true, tipTotal: 1.99, supporterColor: "rose" });
  assert.equal(s.color, "blue");
});

test("$4.99 total unlocks colour", () => {
  assert.equal(supporterInfo({ isSupporter: true, tipTotal: 4.99, supporterColor: "rose" }).color, "rose");
  assert.equal(supporterInfo({ isSupporter: true, tipTotal: 4.98, supporterColor: "rose" }).color, "blue");
  assert.equal(supporterInfo({ isSupporter: true, tipTotal: 5, supporterColor: "purple" }).color, "purple");
  assert.equal("ring" in supporterInfo({ isSupporter: true, tipTotal: 50 }), false);
});

test("unknown colour falls back to blue", () => {
  assert.equal(supporterInfo({ isSupporter: true, tipTotal: 50, supporterColor: "gold" }).color, "blue");
});

test("legend name style preference", () => {
  assert.equal(supporterInfo({ isSupporter: true, supporterNameStyle: "supporter" }).prefersColor, true);
  assert.equal(supporterInfo({ isSupporter: true }).prefersColor, false);
});

test("supporter badge is server-owned", () => {
  const faked = [{ name: "Supporter", icon: "x" }, { name: "First Shift" }];
  assert.deepEqual(withSupporterBadge(faked, false).map((b) => b.name), ["First Shift"]);
  const real = withSupporterBadge(faked, true);
  assert.deepEqual(real.map((b) => b.name), ["First Shift", "Supporter"]);
  assert.equal(real[1].icon, "heart.fill");
});
