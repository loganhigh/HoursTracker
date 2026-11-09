const test = require("node:test");
const assert = require("node:assert");
const { supporterInfo, withSupporterBadge } = require("../src/supporter");

test("non-supporter gets nothing", () => {
  const s = supporterInfo({ tipTotal: 50, supporterColor: "rose" });
  assert.equal(s.isSupporter, false);
  assert.equal(s.ring, false);
});

test("small tip: blue only, choice ignored", () => {
  const s = supporterInfo({ isSupporter: true, tipTotal: 1.99, supporterColor: "rose" });
  assert.deepEqual([s.color, s.ring], ["blue", false]);
});

test("$5 total unlocks colour, $20 the ring", () => {
  assert.equal(supporterInfo({ isSupporter: true, tipTotal: 5, supporterColor: "purple" }).color, "purple");
  assert.equal(supporterInfo({ isSupporter: true, tipTotal: 19.99 }).ring, false);
  assert.equal(supporterInfo({ isSupporter: true, tipTotal: 20.97 }).ring, true);
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
