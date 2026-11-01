// The "logged a shift" activity doc is what fans out friend pushes. It is
// emitted from inside recomputeUserStats, so these pin down what the emitter
// itself writes for a create, a follow-up update, and a repeat.
const test = require("node:test");
const assert = require("node:assert/strict");
const { emitShiftActivityIfNeeded } = require("../src/stats/recompute.js");
const { makeCalendar } = require("../src/stats/localCalendar.js");

const cal = makeCalendar("America/Regina");
const H = 3600000;

function fakeDb() {
  const docs = new Map();
  const ref = (path) => ({
    path,
    collection: (name) => ({ doc: (id) => ref(`${path}/${name}/${id}`) }),
    get: async () => ({ exists: docs.has(path), data: () => docs.get(path) }),
    set: async (data) => { docs.set(path, { ...(docs.get(path) || {}), ...data }); },
  });
  return { docs, collection: (name) => ({ doc: (id) => ref(`${name}/${id}`) }) };
}

function todayShift(id) {
  const start = Date.now() - 9 * H;
  return { id, date: start, start, end: start + 9 * H, breakMinutes: 0, isOffDay: false };
}

const sharing = { privacy: { shareActivity: true } };

test("a new shift writes one shiftLogged event", async () => {
  const db = fakeDb();
  await emitShiftActivityIfNeeded(db, "u1", sharing, null, todayShift("A"), cal);
  const doc = db.docs.get("users/u1/activity/shift_A");
  assert.equal(doc.kind, "shiftLogged");
  assert.equal(doc.metric, 9);
});

test("the follow-up save of the same shift does not emit (so the create must not be dropped)", async () => {
  const db = fakeDb();
  const entry = todayShift("B");
  await emitShiftActivityIfNeeded(db, "u1", sharing, entry, { ...entry, modifiedAt: 1 }, cal);
  assert.equal(db.docs.size, 0);
});

test("activity is not written when the author hides activity", async () => {
  const db = fakeDb();
  await emitShiftActivityIfNeeded(db, "u1", { privacy: { shareActivity: false } }, null, todayShift("C"), cal);
  assert.equal(db.docs.size, 0);
});
