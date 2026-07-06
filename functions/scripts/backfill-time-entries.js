#!/usr/bin/env node
/**
 * One-time backfill: copy users/{uid}/entries → timeEntries and recompute stats.
 *
 * Usage (from functions/):
 *   GOOGLE_APPLICATION_CREDENTIALS=path/to/sa.json node scripts/backfill-time-entries.js
 *   node scripts/backfill-time-entries.js --uid=USER_ID
 */

const { initializeApp, applicationDefault, cert } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { recomputeUserStats } = require("../src/stats/recompute");

function initAdmin() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    initializeApp({ credential: applicationDefault() });
    return;
  }
  initializeApp();
}

async function backfillUser(db, uid) {
  const entriesSnap = await db.collection("users").doc(uid).collection("entries").get();
  if (entriesSnap.empty) {
    console.log(`skip ${uid}: no legacy entries`);
    return;
  }

  let batch = db.batch();
  let count = 0;
  let opsInBatch = 0;
  for (const doc of entriesSnap.docs) {
    const target = db.collection("users").doc(uid).collection("timeEntries").doc(doc.id);
    batch.set(target, doc.data(), { merge: true });
    count += 1;
    opsInBatch += 1;
    if (opsInBatch >= 400) {
      await batch.commit();
      batch = db.batch();
      opsInBatch = 0;
    }
  }
  if (opsInBatch > 0) {
    await batch.commit();
  }

  await recomputeUserStats(db, uid);
  console.log(`backfilled ${uid}: ${count} entries`);
}

async function main() {
  initAdmin();
  const db = getFirestore();
  const uidArg = process.argv.find((a) => a.startsWith("--uid="));
  const singleUid = uidArg ? uidArg.split("=")[1] : null;

  if (singleUid) {
    await backfillUser(db, singleUid);
    return;
  }

  const usersSnap = await db.collection("users").get();
  console.log(`scanning ${usersSnap.size} users…`);
  for (const userDoc of usersSnap.docs) {
    try {
      await backfillUser(db, userDoc.id);
    } catch (err) {
      console.error(`failed ${userDoc.id}:`, err.message || err);
    }
  }
  console.log("done");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
