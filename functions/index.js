/**
 * Hour Tracker — friend shift push notifications.
 */

const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
// v1 is required for the Auth onCreate trigger — gen-2 functions don't
// support non-blocking auth events yet.
const functionsV1 = require("firebase-functions/v1");
const {
  recomputeUserStats,
  updateGlobalLeaderboard,
  totalXPAtLevelStart,
  buildSnapshotsForPrestige,
  deriveProgressionFromEntryXP,
  levelStateFromXP,
} = require("./src/stats/recompute");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

// Admin tools are gated by BOTH the signed-in account's UID and a passcode
// stored in Secret Manager (never committed to source). UID is the stable
// identity Firebase Auth guarantees regardless of sign-in provider — unlike
// an email string, it can't drift if the account uses Sign in with Apple's
// private relay, links a different provider, or the auth token simply omits
// an email claim. This mirrors the same identity check the client already
// uses (DeveloperConfig.isCEO) to decide whether to even show the panel.
const ADMIN_UID = "msUcdbAbaAaS4HDj52CMs0Vzw8j2";
const ADMIN_PASSCODE = defineSecret("ADMIN_PASSCODE");

const db = getFirestore();
const auth = getAuth();
const messaging = getMessaging();

/** Collect FCM registration tokens from profile doc (legacy) and deviceTokens subcollection. */
async function tokensForUser(friendUid, friendData) {
  const tokens = new Set();

  if (friendData) {
    if (typeof friendData.fcmToken === "string" && friendData.fcmToken.length > 0) {
      tokens.add(friendData.fcmToken);
    }
    const map = friendData.fcmTokens;
    if (map && typeof map === "object") {
      for (const value of Object.values(map)) {
        if (typeof value === "string" && value.length > 0) {
          tokens.add(value);
        }
      }
    }
  }

  const deviceSnap = await db
    .collection("users")
    .doc(friendUid)
    .collection("deviceTokens")
    .get();

  for (const doc of deviceSnap.docs) {
    const token = doc.data()?.token;
    if (typeof token === "string" && token.length > 0) {
      tokens.add(token);
    }
  }

  return [...tokens];
}

function friendShiftAlertsEnabled(data) {
  if (!data || data.friendShiftAlerts === undefined) return true;
  return data.friendShiftAlerts !== false;
}

/**
 * Resolve mutual friend UIDs by reading both the legacy per-user subcollection
 * and the top-level `friendships` collection, then verifying reciprocity.
 * Returns a deduplicated array of friend UIDs.
 */
async function getMutualFriendUids(uid) {
  const friendUids = new Set();
  const confirmedViaFriendships = new Set();

  const [legacySnap, snapA, snapB] = await Promise.all([
    db.collection("users").doc(uid).collection("friends").get(),
    db.collection("friendships").where("userA", "==", uid).get(),
    db.collection("friendships").where("userB", "==", uid).get(),
  ]);

  for (const doc of legacySnap.docs) {
    friendUids.add(doc.id);
  }

  for (const doc of snapA.docs) {
    const other = doc.data().userB;
    if (other) {
      friendUids.add(other);
      confirmedViaFriendships.add(other);
    }
  }
  for (const doc of snapB.docs) {
    const other = doc.data().userA;
    if (other) {
      friendUids.add(other);
      confirmedViaFriendships.add(other);
    }
  }

  // friendships docs are inherently mutual — no reciprocal check needed.
  // Legacy-only friends still need the reciprocal subcollection check.
  const mutual = [];
  for (const friendUid of friendUids) {
    if (confirmedViaFriendships.has(friendUid)) {
      mutual.push(friendUid);
      continue;
    }
    const reciprocal = await db
      .collection("users")
      .doc(friendUid)
      .collection("friends")
      .doc(uid)
      .get();
    if (reciprocal.exists) {
      mutual.push(friendUid);
    }
  }

  return mutual;
}

const NUDGE_EMOJIS = new Set(["👍", "💪", "🔥", "😅", "🙏", "✅"]);

async function sendPushToUser(targetUid, friendData, { title, body, dataPayload }) {
  const tokens = await tokensForUser(targetUid, friendData);
  if (tokens.length === 0) return;

  const sends = tokens.map((token) =>
    messaging
      .send({
        token,
        notification: { title, body },
        data: dataPayload,
        apns: {
          payload: {
            aps: {
              sound: "default",
              "thread-id": "friend_nudge",
            },
          },
        },
      })
      .catch(async (err) => {
        const code = err?.errorInfo?.code || err?.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          await removeStaleToken(targetUid, token, friendData);
        }
        console.warn(`FCM send failed user=${targetUid}:`, err?.message || err);
      })
  );

  await Promise.all(sends);
}

exports.notifyFriendsOnShiftLogged = onDocumentCreated(
  {
    document: "users/{authorUid}/activity/{eventId}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    if (!data || data.kind !== "shiftLogged") return;

    const authorUid = event.params.authorUid;
    const eventId = event.params.eventId;
    const authorName = data.authorDisplayName || "A friend";
    const body = data.body || "logged a shift";
    const notificationBody = `${authorName} ${body}`;

    // Idempotency: skip if we already sent notifications for this event.
    const dedupeRef = db.collection("_fcmDedup").doc(`shift_${authorUid}_${eventId}`);
    const dedupeSnap = await dedupeRef.get();
    if (dedupeSnap.exists) return;

    const mutualFriendUids = await getMutualFriendUids(authorUid);
    if (mutualFriendUids.length === 0) return;

    // `expiresAt` lets a Firestore TTL policy on the `_fcmDedup` collection
    // auto-delete these idempotency markers, which are only useful for a short
    // window after the event fires. Without it the collection grows unbounded
    // (one doc per shift event, forever). Enable the policy once with:
    //   gcloud firestore fields ttls update expiresAt \
    //     --collection-group=_fcmDedup --project=hour-tracker-1fa55 --enable-ttl
    await dedupeRef.set({
      sentAt: FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    });

    const sendPromises = [];

    for (const friendUid of mutualFriendUids) {
      const friendUser = await db.collection("users").doc(friendUid).get();
      const friendData = friendUser.data();
      if (!friendShiftAlertsEnabled(friendData)) continue;

      const tokens = await tokensForUser(friendUid, friendData);
      if (tokens.length === 0) continue;

      for (const token of tokens) {
        sendPromises.push(
          messaging
            .send({
              token,
              notification: {
                title: "Your friend logged a shift!",
                body: notificationBody,
              },
              data: {
                type: "friend_shift",
                authorUid,
                eventId,
                kind: "shiftLogged",
              },
              apns: {
                payload: {
                  aps: {
                    sound: "default",
                    "thread-id": "friend_activity",
                  },
                },
              },
            })
            .catch(async (err) => {
              const code = err?.errorInfo?.code || err?.code;
              if (
                code === "messaging/registration-token-not-registered" ||
                code === "messaging/invalid-registration-token"
              ) {
                await removeStaleToken(friendUid, token, friendData);
              }
              console.warn(
                `FCM send failed friend=${friendUid} event=${eventId}:`,
                err?.message || err
              );
            })
        );
      }
    }

    await Promise.all(sendPromises);
  }
);

/**
 * Notify the developer account whenever a brand-new user account is created
 * (first sign-in with Apple/Google creates the Firebase Auth user, so this
 * fires exactly once per new user).
 */
exports.notifyAdminOnNewUser = functionsV1
  .region("us-central1")
  .auth.user()
  .onCreate(async (user) => {
    if (user.uid === ADMIN_UID) return;

    const name = user.displayName || "";
    const email = user.email || "";
    const provider = user.providerData?.[0]?.providerId || "unknown";
    const who = name || email || `uid ${user.uid.slice(0, 8)}…`;

    const adminSnap = await db.collection("users").doc(ADMIN_UID).get();
    await sendPushToUser(ADMIN_UID, adminSnap.data(), {
      title: "New Hour Tracker user!",
      body: `${who} just signed in for the first time (${provider}).`,
      dataPayload: {
        type: "admin_new_user",
        newUserUid: user.uid,
      },
    });
  });

exports.notifyOnShiftNudge = onDocumentCreated(
  {
    document: "users/{targetUid}/shiftNudges/{nudgeId}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    if (!data || data.status !== "pending") return;

    const targetUid = event.params.targetUid;
    const fromName = data.fromName || "A friend";

    const targetUser = await db.collection("users").doc(targetUid).get();
    const targetData = targetUser.data();
    if (!friendShiftAlertsEnabled(targetData)) return;

    await sendPushToUser(targetUid, targetData, {
      title: "Shift reminder",
      body: `${fromName} nudged you to log your shifts — tap to reply with an emoji`,
      dataPayload: {
        type: "friend_nudge",
        nudgeId: event.params.nudgeId,
        fromUid: data.fromUid || "",
      },
    });
  }
);

exports.notifySenderOnShiftNudgeReaction = onDocumentUpdated(
  {
    document: "users/{targetUid}/shiftNudges/{nudgeId}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return;
    if (before.status === "reacted" || after.status !== "reacted") return;

    const reaction = after.reaction;
    if (!reaction || !NUDGE_EMOJIS.has(reaction)) return;

    const senderUid = after.fromUid;
    if (!senderUid) return;

    const senderUser = await db.collection("users").doc(senderUid).get();
    const senderData = senderUser.data();
    if (!friendShiftAlertsEnabled(senderData)) return;

    const targetUid = event.params.targetUid;
    const targetUser = await db.collection("users").doc(targetUid).get();
    const responderName =
      targetUser.data()?.displayName ||
      targetUser.data()?.profileDisplayName ||
      "Your friend";

    await sendPushToUser(senderUid, senderData, {
      title: "Nudge reply",
      body: `${responderName} replied ${reaction}`,
      dataPayload: {
        type: "friend_nudge_reaction",
        nudgeId: event.params.nudgeId,
        reaction,
        fromUid: targetUid,
      },
    });
  }
);

/**
 * Triggered when a user writes a friend request doc.
 * Sends a push notification to the recipient.
 */
exports.notifyOnFriendRequest = onDocumentCreated(
  {
    document: "users/{targetUid}/friendRequests/{fromUid}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    if (!data) return;

    const targetUid = event.params.targetUid;
    const fromName = data.fromName || "Someone";

    const targetUser = await db.collection("users").doc(targetUid).get();
    const targetData = targetUser.data();

    await sendPushToUser(targetUid, targetData, {
      title: "New friend request",
      body: `${fromName} sent you a friend request`,
      dataPayload: {
        type: "friend_request",
        fromUid: event.params.fromUid,
        fromName: data.fromName || "",
      },
    });
  }
);

/**
 * Daily at 09:00 UTC — finds users whose work start date anniversary falls
 * on today and pushes a notification to each of their mutual friends.
 */
exports.notifyFriendsOnWorkAnniversary = onSchedule(
  {
    schedule: "0 9 * * *",
    timeZone: "UTC",
    region: "us-central1",
  },
  async () => {
    const today = new Date();
    const todayMonth = today.getUTCMonth() + 1;
    const todayDay = today.getUTCDate();

    // Fetch every user that has a companyStartDate stored
    const usersSnap = await db
      .collection("users")
      .where("companyStartDate", "!=", null)
      .get();

    if (usersSnap.empty) return;

    for (const userDoc of usersSnap.docs) {
      const userData = userDoc.data();
      const companyStartDate = userData.companyStartDate?.toDate?.();
      if (!companyStartDate) continue;

      // Only act if today is the month/day of their start date
      if (
        companyStartDate.getUTCMonth() + 1 !== todayMonth ||
        companyStartDate.getUTCDate() !== todayDay
      ) continue;

      // Don't fire on the day they joined — only on actual anniversaries
      const years = today.getUTCFullYear() - companyStartDate.getUTCFullYear();
      if (years <= 0) continue;

      const uid = userDoc.id;
      const displayName =
        userData.displayName || userData.profileDisplayName || "Your friend";
      const companyName = userData.companyName || "";
      const yearLabel = years === 1 ? "year" : "years";

      const title = "Work Anniversary 🎉";
      const body = companyName
        ? `${displayName} is celebrating ${years} ${yearLabel} at ${companyName}!`
        : `${displayName} is celebrating ${years} ${yearLabel} at their company!`;

      // Notify each mutual friend
      const mutualFriendUids = await getMutualFriendUids(uid);

      for (const friendUid of mutualFriendUids) {
        const friendUser = await db.collection("users").doc(friendUid).get();
        const friendData = friendUser.data();

        await sendPushToUser(friendUid, friendData, {
          title,
          body,
          dataPayload: {
            type: "work_anniversary",
            authorUid: uid,
            years: String(years),
          },
        });
      }
    }
  }
);

const REFRESH_PROGRESS_REF_PATH = ["adminOps", "refreshAllUsers"];
/** A single stuck user (e.g. an abnormally large timeEntries collection) must
 * not stall the whole batch until the outer function timeout fires — that's
 * what previously made the operation look "hung" with no visible progress.
 * Cap each individual recompute and count it as failed if it doesn't finish. */
const PER_USER_TIMEOUT_MS = 20000;

function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`timed out after ${ms}ms`)), ms)
    ),
  ]);
}

/**
 * Recomputes every user's stats, in bounded-concurrency chunks. Shared by the
 * daily scheduled safety net and the on-demand admin callable below. This is
 * also what backfills `publicProfiles/{uid}` for users who haven't triggered
 * a recompute since that collection was introduced — that doc is created
 * lazily on first recompute, so anyone who hasn't logged a shift since the
 * dual-write migration simply won't have one yet without this running.
 *
 * Progress is written to `adminOps/refreshAllUsers` after every chunk so the
 * admin panel can show live counts instead of an indefinite spinner, and so a
 * stall can be diagnosed (which uid it stopped on) instead of just looking
 * "stuck" with no visibility into what actually happened server-side.
 */
async function refreshAllUsersStats(db) {
  const startedAtMs = Date.now();
  console.log("refreshAllUsersStats: start");
  const progressRef = db.collection(REFRESH_PROGRESS_REF_PATH[0]).doc(REFRESH_PROGRESS_REF_PATH[1]);
  await progressRef.set({
    running: true,
    total: 0,
    processed: 0,
    succeeded: 0,
    failed: 0,
    startedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  try {
    const [usersSnap, authResult] = await Promise.all([
      db.collection("users").select().get(),
      auth.listUsers(1000),
    ]);
    console.log(
      `refreshAllUsersStats: fetched ${usersSnap.size} users docs + ${authResult.users.length} auth users (+${Date.now() - startedAtMs}ms)`
    );

    const uids = new Set(usersSnap.docs.map((d) => d.id));

    // Auth accounts (e.g. Sign in with Apple) that never got a Firestore profile
    // doc still need a users/{uid} stub before recompute can publish stats.
    for (const authUser of authResult.users) {
      if (uids.has(authUser.uid)) continue;
      const email = authUser.email || "";
      const fallbackName = email.includes("@") ? email.split("@")[0] : "Worker";
      await db.collection("users").doc(authUser.uid).set(
        {
          displayName: authUser.displayName || fallbackName,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      uids.add(authUser.uid);
    }
    console.log(`refreshAllUsersStats: stub creation done, ${uids.size} total uids (+${Date.now() - startedAtMs}ms)`);

    const uidList = [...uids];
    let succeeded = 0;
    let failed = 0;
    let skipped = 0;
    await progressRef.set({ total: uidList.length, updatedAt: FieldValue.serverTimestamp() }, { merge: true });

    // Strictly sequential (no concurrency at all). The previous concurrent
    // version silently killed the whole container mid-batch with zero error
    // output — not even the per-user timeout's rejection fired, which only
    // happens when the *process itself* dies (almost certainly OOM: several
    // large timeEntries histories loaded into memory at once). One user at a
    // time keeps peak memory to whatever the single largest account needs,
    // trading speed for actually finishing reliably.
    for (let i = 0; i < uidList.length; i++) {
      const uid = uidList[i];
      console.log(`refreshAllUsersStats: [${i + 1}/${uidList.length}] starting uid=${uid} (+${Date.now() - startedAtMs}ms)`);
      try {
        const result = await withTimeout(
          recomputeUserStats(db, uid, {
            skipLeaderboardUpdate: true,
            skipFence: true,
          }),
          PER_USER_TIMEOUT_MS
        );
        if (result?.skipped) skipped += 1;
        else succeeded += 1;
      } catch (err) {
        failed += 1;
        console.warn(`refreshAllUsersStats failed uid=${uid}:`, err?.message || err);
      }
      await progressRef.set(
        {
          processed: i + 1,
          succeeded,
          failed,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
    console.log(`refreshAllUsersStats: all users processed (+${Date.now() - startedAtMs}ms)`);
    try {
      await updateGlobalLeaderboard(db);
    } catch (err) {
      console.warn("refreshAllUsersStats: final leaderboard update failed:", err?.message || err);
    }
    console.log(
      `refreshAllUsersStats done total=${uidList.length} succeeded=${succeeded} failed=${failed} auth=${authResult.users.length}`
    );
    await progressRef.set(
      {
        running: false,
        finishedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return {
      total: uidList.length,
      succeeded,
      failed,
      authCount: authResult.users.length,
    };
  } catch (err) {
    console.error("refreshAllUsersStats: fatal error", err?.message || err);
    await progressRef.set(
      {
        running: false,
        error: err?.message || String(err),
        finishedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    throw err;
  }
}

function buildAdminUserRow(uid, userData, profileData) {
  const u = userData || {};
  const p = profileData || {};
  const hasPublicProfile = Object.keys(p).length > 0;
  return {
    uid,
    displayName: p.displayName || u.displayName || "",
    level: Number(p.level) || Number(u.level) || 1,
    prestige: Number(p.prestige) || Number(u.prestige) || 0,
    totalHours:
      Math.round((Number(p.totalHours) || Number(u.totalHours) || 0) * 100) / 100,
    adminFloorLevel:
      u.adminFloorLevel != null ? Number(u.adminFloorLevel) : null,
    adminFloorPrestige:
      u.adminFloorPrestige != null ? Number(u.adminFloorPrestige) : null,
    adminEquippedTitle: u.adminEquippedTitle || "",
    equippedTitle:
      p.equippedTitle || u.adminEquippedTitle || u.equippedTitle || "",
    countryCode: String(u.countryCode || p.countryCode || "").trim().toUpperCase(),
    profilePending: !hasPublicProfile,
  };
}

/**
 * Daily safety net: re-recomputes every user's stats even without a new
 * timeEntries write. Several published fields are time-relative rather than
 * purely a function of the entries (current streak decays if today wasn't
 * logged; the current pay cheque rolls over on its boundary date) — without
 * this, a user who stops logging shifts would appear frozen on an old
 * snapshot to their friends indefinitely, since nothing would ever trigger
 * a fresh compute. Runs once daily.
 */
exports.dailyStatsRefresh = onSchedule(
  {
    schedule: "0 8 * * *",
    timeZone: "UTC",
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    await refreshAllUsersStats(db);
  }
);

/**
 * Admin-only: run the same bulk refresh as the daily job, but on demand —
 * e.g. to immediately backfill publicProfiles for every existing user
 * instead of waiting for the next scheduled run.
 */
exports.adminRefreshAllUsers = onCall(
  {
    region: "us-central1",
    secrets: [ADMIN_PASSCODE],
    timeoutSeconds: 300,
    // Even at 512MiB with 10-wide concurrency, this container was silently
    // OOM-killed mid-batch (confirmed via logs: execution just stops with no
    // error). Combined with switching to fully sequential processing, this
    // extra headroom should make that class of failure a non-issue.
    memory: "1GiB",
  },
  async (request) => {
    assertAdmin(request);
    const result = await refreshAllUsersStats(db);
    return { ok: true, ...result };
  }
);

/**
 * Polled by the admin panel while a bulk refresh is running so it can show
 * live counts. A dedicated callable (rather than a client-side Firestore
 * listener) reuses the exact same UID+passcode auth path already proven to
 * work for the other admin callables, instead of adding a second, separate
 * client-side permission surface (Firestore rules) that can fail silently.
 */
exports.adminRefreshProgress = onCall(
  { region: "us-central1", secrets: [ADMIN_PASSCODE] },
  async (request) => {
    assertAdmin(request);
    const snap = await db.collection(REFRESH_PROGRESS_REF_PATH[0]).doc(REFRESH_PROGRESS_REF_PATH[1]).get();
    if (!snap.exists) return { exists: false };
    const d = snap.data();
    return {
      exists: true,
      running: d.running === true,
      total: d.total || 0,
      processed: d.processed || 0,
      succeeded: d.succeeded || 0,
      failed: d.failed || 0,
      error: d.error || null,
    };
  }
);

async function removeStaleToken(friendUid, staleToken, data) {
  const updates = {};

  if (data?.fcmToken === staleToken) {
    updates.fcmToken = FieldValue.delete();
  }

  const map = data?.fcmTokens;
  if (map && typeof map === "object") {
    for (const [deviceId, token] of Object.entries(map)) {
      if (token === staleToken) {
        updates[`fcmTokens.${deviceId}`] = FieldValue.delete();
      }
    }
  }

  if (Object.keys(updates).length > 0) {
    await db.collection("users").doc(friendUid).update(updates);
  }

  const deviceSnap = await db
    .collection("users")
    .doc(friendUid)
    .collection("deviceTokens")
    .get();

  for (const doc of deviceSnap.docs) {
    if (doc.data()?.token === staleToken) {
      await doc.ref.delete();
    }
  }
}

/** Recompute stats when a time entry is written (primary server pipeline). */
exports.onTimeEntryWritten = onDocumentWritten(
  {
    document: "users/{uid}/timeEntries/{entryId}",
    region: "us-central1",
  },
  async (event) => {
    const uid = event.params.uid;
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;
    const beforeEntry = before ? { id: event.params.entryId, ...before } : null;
    const afterEntry = after ? { id: event.params.entryId, ...after } : null;
    try {
      // Do NOT rebuild the global leaderboard here. This trigger fires on every
      // shift create/edit/delete by every user, and updateGlobalLeaderboard
      // scans the ENTIRE publicProfiles collection — making Firestore reads grow
      // as O(users x writes). The leaderboard is refreshed on its own schedule
      // by `leaderboardRefresh` (below) and by the daily bulk refresh instead.
      await recomputeUserStats(db, uid, { beforeEntry, afterEntry, skipLeaderboardUpdate: true });
    } catch (err) {
      console.error(`recomputeUserStats failed uid=${uid}:`, err?.message || err);
      throw err;
    }
  }
);

/**
 * Rebuild the global leaderboard on a fixed cadence rather than on every shift
 * write. This decouples leaderboard cost from write volume: it now costs
 * O(users) reads per run at a predictable frequency, instead of O(users) reads
 * per shift logged app-wide. 15 minutes keeps rankings fresh enough for a
 * social leaderboard while the per-write trigger stays cheap.
 */
exports.leaderboardRefresh = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "UTC",
    region: "us-central1",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    await updateGlobalLeaderboard(db);
  }
);

/** Client health check: write debugEvents via Admin SDK (bypasses hung device writes). */
exports.clientCloudWriteHealthCheck = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;
    const token = typeof request.data?.token === "string" && request.data.token.length > 0
      ? request.data.token
      : `server-${Date.now()}`;
    await db.collection("users").doc(uid).collection("debugEvents").doc("writeHealthCheck").set({
      status: "ok",
      uid,
      token,
      source: "cloud_function",
      clientSyncBuild: "repair-diagnostics-v4",
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { status: "ok", token };
  }
);

/** Bulk upload time entries when direct Firestore writes hang on-device. */
exports.clientUploadTimeEntriesBatch = onCall(
  { region: "us-central1", memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;
    const entries = request.data?.entries;
    if (!Array.isArray(entries) || entries.length === 0) {
      throw new HttpsError("invalid-argument", "entries array is required.");
    }
    if (entries.length > 200) {
      throw new HttpsError("invalid-argument", "Max 200 entries per batch.");
    }

    let batch = db.batch();
    let ops = 0;
    let written = 0;

    const commitIfNeeded = async (force = false) => {
      if (ops === 0) return;
      if (!force && ops < 400) return;
      await batch.commit();
      batch = db.batch();
      ops = 0;
    };

    for (const raw of entries) {
      if (!raw || typeof raw !== "object") continue;
      const entryId = String(raw.id || raw.entryId || "").trim();
      if (!entryId) continue;
      const payload = {
        ...raw,
        updatedAt: FieldValue.serverTimestamp(),
      };
      const timeRef = db.collection("users").doc(uid).collection("timeEntries").doc(entryId);
      const legacyRef = db.collection("users").doc(uid).collection("entries").doc(entryId);
      batch.set(timeRef, payload, { merge: true });
      batch.set(legacyRef, payload, { merge: true });
      ops += 2;
      written += 1;
      if (ops >= 400) {
        await commitIfNeeded(true);
      }
    }

    await commitIfNeeded(true);
    if (written > 0) {
      await recomputeUserStats(db, uid, { skipFence: true, skipLeaderboardUpdate: true });
    }
    return { status: "ok", uploaded: written };
  }
);

/** Admin/support callable to repair a user's stats from all timeEntries. */
exports.recomputeUserStatsCallable = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.data?.uid || request.auth.uid;
    if (uid !== request.auth.uid) {
      throw new HttpsError("permission-denied", "Can only recompute your own stats.");
    }
    await recomputeUserStats(db, uid);
    return { ok: true, uid };
  }
);

/**
 * Admin-only: force a stats recompute for ANY user by uid. Used to repair a
 * friend's stale friend-facing data (e.g. missing cheque breakdown) without
 * waiting for them to log a shift. Gated by the admin account UID AND a
 * passcode stored in Secret Manager.
 */
exports.adminRecomputeUserStats = onCall(
  { region: "us-central1", secrets: [ADMIN_PASSCODE] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    if (request.auth.uid !== ADMIN_UID) {
      throw new HttpsError("permission-denied", "Admins only.");
    }
    if ((request.data?.passcode || "") !== ADMIN_PASSCODE.value()) {
      throw new HttpsError("permission-denied", "Invalid admin passcode.");
    }
    const targetUid = request.data?.targetUid;
    if (!targetUid || typeof targetUid !== "string") {
      throw new HttpsError("invalid-argument", "targetUid is required.");
    }
    await recomputeUserStats(db, targetUid);
    return { ok: true, targetUid };
  }
);

/** Shared admin gate: signed in, correct account UID, and valid passcode. */
function assertAdmin(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  if (request.auth.uid !== ADMIN_UID) {
    throw new HttpsError("permission-denied", "Admins only.");
  }
  if ((request.data?.passcode || "") !== ADMIN_PASSCODE.value()) {
    throw new HttpsError("permission-denied", "Invalid admin passcode.");
  }
}

/** Sets current level and/or prestige; shifts still add XP afterward. */
async function applyAdminProgressionSet(db, targetUid, opts = {}) {
  const { targetLevel, targetPrestige } = opts;
  const userRef = db.collection("users").doc(targetUid);
  const gamRef = userRef.collection("gamification").doc("current");
  const [gamSnap, userSnap] = await Promise.all([gamRef.get(), userRef.get()]);
  const g = gamSnap.data() || {};
  const u = userSnap.data() || {};
  const existingOffset = Number(g.adminXPOffset) || 0;
  const syncedTotal = Number(g.totalXP) || Number(u.totalXP) || 0;
  const entryXP = syncedTotal - existingOffset;

  const prestige =
    targetPrestige != null
      ? Math.min(10, Math.max(0, Math.floor(Number(targetPrestige))))
      : Math.min(
          10,
          Math.max(0, Number(g.prestige) || Number(u.prestige) || 0)
        );

  const snapshots =
    targetPrestige != null
      ? buildSnapshotsForPrestige(prestige)
      : Array.isArray(g.prestigeXPSnapshots)
        ? g.prestigeXPSnapshots
        : [];

  let level;
  if (targetLevel != null) {
    level = Math.min(25, Math.max(1, Math.floor(Number(targetLevel))));
  } else if (targetPrestige != null) {
    level = 1;
  } else {
    level = levelStateFromXP(entryXP, prestige, snapshots);
  }

  const targetStart = totalXPAtLevelStart(level, prestige, snapshots);
  const newOffset = targetStart - entryXP;
  const newTotal = entryXP + newOffset;
  const highWater = Math.max(Number(g.highWaterPrestige) || 0, prestige);

  const gamUpdate = {
    prestige,
    prestigeFloor: highWater,
    highWaterPrestige: highWater,
    adminXPOffset: newOffset,
    totalXP: newTotal,
    updatedAt: FieldValue.serverTimestamp(),
    // The offset + totalXP + prestige/snapshots above fully encode the set.
    // Do NOT write levelOverride/prestigeOverride flags: they required every
    // client to consume-and-clear them, and any client that failed to clear
    // (old build, race, crash) re-applied the set on every subsequent
    // listener fire — snapping XP back and replaying level-ups repeatedly.
    // Deleting them here also cleans up flags left behind by earlier sets.
    levelOverride: FieldValue.delete(),
    prestigeOverride: FieldValue.delete(),
  };
  if (targetPrestige != null) {
    gamUpdate.prestigeXPSnapshots =
      prestige > 0 ? snapshots : FieldValue.delete();
  }

  const batch = db.batch();
  batch.set(gamRef, gamUpdate, { merge: true });
  batch.set(
    userRef,
    { adminFloorLevel: FieldValue.delete(), adminFloorPrestige: FieldValue.delete() },
    { merge: true }
  );
  await batch.commit();
}

/** Clears admin level/prestige sets — returns to shift-derived progression. */
async function clearAdminProgressionSet(db, targetUid) {
  const userRef = db.collection("users").doc(targetUid);
  const gamRef = userRef.collection("gamification").doc("current");
  const gamSnap = await gamRef.get();
  const g = gamSnap.data() || {};
  const existingOffset = Number(g.adminXPOffset) || 0;
  const syncedTotal = Number(g.totalXP) || 0;
  const entryXP = syncedTotal - existingOffset;
  const derived = deriveProgressionFromEntryXP(entryXP);

  await gamRef.set(
    {
      adminXPOffset: 0,
      totalXP: entryXP,
      prestige: derived.prestige,
      prestigeFloor: derived.prestige,
      highWaterPrestige: Math.max(
        Number(g.highWaterPrestige) || 0,
        derived.prestige
      ),
      prestigeXPSnapshots:
        derived.snapshots.length > 0 ? derived.snapshots : FieldValue.delete(),
      levelOverride: FieldValue.delete(),
      prestigeOverride: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  await userRef.set(
    { adminFloorLevel: FieldValue.delete(), adminFloorPrestige: FieldValue.delete() },
    { merge: true }
  );
}

/**
 * Admin-only: list every user for the in-app admin panel. Reads ALL
 * users/{uid} docs (everyone who has ever opened the app) plus any Firebase
 * Auth accounts that signed in but never got a Firestore profile yet. Stats
 * prefer the server-maintained publicProfiles doc, falling back to the legacy
 * mirror on users/{uid} so accounts still appear even before backfill runs.
 */
exports.adminListUsers = onCall(
  { region: "us-central1", secrets: [ADMIN_PASSCODE] },
  async (request) => {
    assertAdmin(request);

    const [usersSnap, profilesSnap, authResult] = await Promise.all([
      db.collection("users").get(),
      db.collection("publicProfiles").get(),
      auth.listUsers(1000),
    ]);

    const profileByUid = new Map(
      profilesSnap.docs.map((doc) => [doc.id, doc.data() || {}])
    );
    const firestoreUids = new Set(usersSnap.docs.map((doc) => doc.id));

    const rows = usersSnap.docs.map((doc) =>
      buildAdminUserRow(doc.id, doc.data(), profileByUid.get(doc.id))
    );

    for (const authUser of authResult.users) {
      if (firestoreUids.has(authUser.uid)) continue;
      const email = authUser.email || "";
      const fallbackName = email.includes("@") ? email.split("@")[0] : "Worker";
      rows.push(
        buildAdminUserRow(authUser.uid, {
          displayName: authUser.displayName || fallbackName,
        }, null)
      );
    }

    rows.sort((a, b) => b.totalHours - a.totalHours);

    return {
      ok: true,
      users: rows,
      firestoreCount: usersSnap.size,
      authCount: authResult.users.length,
      publicProfileCount: profilesSnap.size,
    };
  }
);

/**
 * Admin-only: set a user's current level (via XP offset), prestige floor,
 * title override, or country flag. Level sets become the user's current level
 * and they continue earning XP normally afterward. Passing null for level
 * resets progression to shift-derived XP only.
 */
exports.adminSetUserProgression = onCall(
  { region: "us-central1", secrets: [ADMIN_PASSCODE] },
  async (request) => {
    assertAdmin(request);

    const targetUid = request.data?.targetUid;
    if (!targetUid || typeof targetUid !== "string") {
      throw new HttpsError("invalid-argument", "targetUid is required.");
    }

    const update = {};
    const rawLevel = request.data?.level;
    const rawPrestige = request.data?.prestige;
    const rawTitle =
      request.data?.equippedTitle !== undefined
        ? request.data.equippedTitle
        : request.data?.adminEquippedTitle;
    const rawCountry = request.data?.countryCode;
    let touchesProgressionSet = false;

    const resettingProgression = rawLevel === null && rawPrestige === null;
    if (resettingProgression) {
      update.adminFloorLevel = FieldValue.delete();
      update.adminFloorPrestige = FieldValue.delete();
      await clearAdminProgressionSet(db, targetUid);
      touchesProgressionSet = true;
    } else {
      let targetLevel;
      let targetPrestige;

      if (rawLevel !== undefined && rawLevel !== null) {
        const lvl = Math.floor(Number(rawLevel));
        if (!Number.isFinite(lvl) || lvl < 0) {
          throw new HttpsError("invalid-argument", "level must be >= 0.");
        }
        if (lvl > 25) {
          throw new HttpsError("invalid-argument", "level cannot exceed 25.");
        }
        if (lvl > 0) targetLevel = lvl;
      }

      if (rawPrestige !== undefined && rawPrestige !== null) {
        const pres = Math.floor(Number(rawPrestige));
        if (!Number.isFinite(pres) || pres < 0) {
          throw new HttpsError("invalid-argument", "prestige must be >= 0.");
        }
        if (pres > 10) {
          throw new HttpsError("invalid-argument", "prestige cannot exceed 10.");
        }
        targetPrestige = pres;
      }

      if (targetLevel !== undefined || targetPrestige !== undefined) {
        await applyAdminProgressionSet(db, targetUid, {
          targetLevel,
          targetPrestige,
        });
        touchesProgressionSet = true;
      }
    }

    if (rawPrestige === null && !resettingProgression) {
      update.adminFloorPrestige = FieldValue.delete();
    }
    if (rawLevel === null && !resettingProgression) {
      update.adminFloorLevel = FieldValue.delete();
    }

    if (rawTitle === null) {
      update.adminEquippedTitle = FieldValue.delete();
    } else if (rawTitle !== undefined) {
      const title = String(rawTitle).trim();
      if (!title) {
        update.adminEquippedTitle = FieldValue.delete();
      } else if (title.length > 40) {
        throw new HttpsError("invalid-argument", "Title must be 40 characters or fewer.");
      } else {
        update.adminEquippedTitle = title;
      }
    }

    if (rawCountry === null) {
      update.countryCode = FieldValue.delete();
    } else if (rawCountry !== undefined) {
      const code = String(rawCountry).trim().toUpperCase();
      if (!code) {
        update.countryCode = FieldValue.delete();
      } else if (!/^[A-Z]{2}$/.test(code)) {
        throw new HttpsError(
          "invalid-argument",
          "countryCode must be a 2-letter ISO code (e.g. CA, US)."
        );
      } else {
        update.countryCode = code;
      }
    }

    if (Object.keys(update).length === 0 && !touchesProgressionSet) {
      throw new HttpsError("invalid-argument", "Nothing to update.");
    }

    if (Object.keys(update).length > 0) {
      await db.collection("users").doc(targetUid).set(update, { merge: true });
    }

    const touchesCountry = Object.prototype.hasOwnProperty.call(update, "countryCode");
    const touchesProgression =
      touchesProgressionSet ||
      Object.prototype.hasOwnProperty.call(update, "adminEquippedTitle");

    // Mirror admin-set country onto publicProfiles immediately so the
    // leaderboard can pick it up without a full stats recompute.
    if (touchesCountry) {
      const pubCountry =
        update.countryCode === FieldValue.delete() ? "" : update.countryCode;
      await db
        .collection("publicProfiles")
        .doc(targetUid)
        .set({ countryCode: pubCountry }, { merge: true });
    }

    if (touchesProgression) {
      await recomputeUserStats(db, targetUid, {
        skipFence: true,
        skipLeaderboardUpdate: true,
      });
    }
    if (touchesCountry || touchesProgression) {
      await updateGlobalLeaderboard(db);
    }

    const userSnap = await db.collection("users").doc(targetUid).get();
    const profileSnap = await db.collection("publicProfiles").doc(targetUid).get();
    const u = userSnap.data() || {};
    const p = profileSnap.data() || {};
    return {
      status: "ok",
      targetUid,
      adminFloorLevel:
        u.adminFloorLevel != null ? Number(u.adminFloorLevel) : null,
      adminFloorPrestige:
        u.adminFloorPrestige != null ? Number(u.adminFloorPrestige) : null,
      adminEquippedTitle: u.adminEquippedTitle || "",
      level: Number(u.level) || null,
      prestige: Number(u.prestige) || null,
      equippedTitle:
        p.equippedTitle || u.adminEquippedTitle || u.equippedTitle || "",
      countryCode: String(u.countryCode || p.countryCode || "").trim().toUpperCase(),
    };
  }
);

exports.adminClearAllFloors = onCall(
  { region: "us-central1", secrets: [ADMIN_PASSCODE], timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    assertAdmin(request);
    const usersSnap = await db.collection("users").get();
    let cleared = 0;
    let batch = db.batch();
    let ops = 0;
    const commitBatch = async () => {
      if (ops === 0) return;
      await batch.commit();
      batch = db.batch();
      ops = 0;
    };
    for (const doc of usersSnap.docs) {
      const data = doc.data() || {};
      const updates = {};
      if (data.adminFloorLevel != null) updates.adminFloorLevel = FieldValue.delete();
      if (data.adminFloorPrestige != null) updates.adminFloorPrestige = FieldValue.delete();
      if (Object.keys(updates).length > 0) {
        batch.set(doc.ref, updates, { merge: true });
        cleared += 1;
        ops += 1;
        if (ops >= 450) await commitBatch();
      }
    }
    await commitBatch();
    for (const doc of usersSnap.docs) {
      const gamSnap = await doc.ref.collection("gamification").doc("current").get();
      const g = gamSnap.data() || {};
      if ((Number(g.adminXPOffset) || 0) !== 0) {
        await clearAdminProgressionSet(db, doc.id);
        cleared += 1;
        continue;
      }
      const data = doc.data() || {};
      if (data.adminFloorLevel != null || data.adminFloorPrestige != null) {
        await clearAdminProgressionSet(db, doc.id);
        cleared += 1;
      }
    }
    const result = await refreshAllUsersStats(db);
    return { status: "ok", cleared, ...result };
  }
);

exports.adminRefreshLeaderboard = onCall(
  { region: "us-central1", secrets: [ADMIN_PASSCODE] },
  async (request) => {
    assertAdmin(request);
    await updateGlobalLeaderboard(db);
    const snap = await db.collection("leaderboards").doc("global").get();
    const data = snap.data() || {};
    return {
      status: "ok",
      totalRanked: data.totalRanked || 0,
    };
  }
);

/**
 * Backfill friendships collection from legacy users/{uid}/friends subcollection.
 * Idempotent — skips pairs that already exist. Each user only backfills their
 * own friends; both sides calling this converges to the same result.
 */
exports.backfillFriendships = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;
    const friendsSnap = await db
      .collection("users")
      .doc(uid)
      .collection("friends")
      .get();

    if (friendsSnap.empty) return { ok: true, backfilled: 0 };

    let backfilled = 0;
    const batch = db.batch();

    for (const doc of friendsSnap.docs) {
      const friendUid = doc.documentID || doc.id;
      const sorted = [uid, friendUid].sort();
      const pairId = `${sorted[0]}_${sorted[1]}`;
      const ref = db.collection("friendships").doc(pairId);
      const existing = await ref.get();
      if (existing.exists) continue;

      const reciprocal = await db
        .collection("users")
        .doc(friendUid)
        .collection("friends")
        .doc(uid)
        .get();
      if (!reciprocal.exists) continue;

      const addedAt = doc.data()?.addedAt || FieldValue.serverTimestamp();
      batch.set(ref, {
        userA: sorted[0],
        userB: sorted[1],
        createdAt: addedAt,
        createdBy: uid,
      });
      backfilled++;
    }

    if (backfilled > 0) {
      await batch.commit();
    }

    return { ok: true, backfilled };
  }
);

/** Add a friend by code — validates code, checks duplicates, connects instantly. */
exports.sendFriendRequest = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const myUid = request.auth.uid;
    const code = (request.data?.code || "").trim().toUpperCase();
    const myName = request.data?.myName || "Friend";

    if (!code || code.length < 4) {
      throw new HttpsError("invalid-argument", "Enter a valid friend code.");
    }

    // Look up target user by friend code
    const usersSnap = await db.collection("users")
      .where("friendCode", "==", code).limit(1).get();
    if (usersSnap.empty) {
      throw new HttpsError("not-found", "No one found with that code.");
    }
    const targetDoc = usersSnap.docs[0];
    const targetUid = targetDoc.id;
    if (targetUid === myUid) {
      throw new HttpsError("invalid-argument", "You can't add yourself.");
    }

    // Check if already friends (either path)
    const [legacyFriend, friendshipA] = await Promise.all([
      db.collection("users").doc(myUid).collection("friends").doc(targetUid).get(),
      (() => {
        const sorted = [myUid, targetUid].sort();
        return db.collection("friendships").doc(`${sorted[0]}_${sorted[1]}`).get();
      })(),
    ]);
    if (legacyFriend.exists || friendshipA.exists) {
      throw new HttpsError("already-exists", "You're already friends.");
    }

    // Check acceptInvites
    const targetData = targetDoc.data() || {};
    if (targetData.acceptInvites === false) {
      throw new HttpsError("permission-denied", "This user isn't accepting invites.");
    }

    // Adding by code connects instantly — no pending approval step. Create
    // the friendship on both sides right away, and clean up any stray
    // pending-request docs left over from before this became instant.
    const batch = db.batch();
    const now = FieldValue.serverTimestamp();
    batch.set(db.collection("users").doc(myUid).collection("friends").doc(targetUid),
      { friendUid: targetUid, addedAt: now });
    batch.set(db.collection("users").doc(targetUid).collection("friends").doc(myUid),
      { friendUid: myUid, addedAt: now });
    batch.delete(db.collection("users").doc(myUid).collection("friendRequests").doc(targetUid));
    batch.delete(db.collection("users").doc(targetUid).collection("friendRequests").doc(myUid));
    const sorted = [myUid, targetUid].sort();
    const pairId = `${sorted[0]}_${sorted[1]}`;
    batch.set(db.collection("friendships").doc(pairId), {
      userA: sorted[0],
      userB: sorted[1],
      createdAt: now,
      createdBy: myUid,
    });
    await batch.commit();

    await sendPushToUser(targetUid, targetData, {
      title: "New friend added",
      body: `${myName} added you as a friend`,
      dataPayload: {
        type: "friend_added",
        fromUid: myUid,
        fromName: myName,
      },
    });

    return { ok: true, targetUid, autoAccepted: true };
  }
);

/** Accept a friend request — creates both friend links, friendships doc, cleans up requests. */
exports.acceptFriendRequest = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const myUid = request.auth.uid;
    const fromUid = request.data?.fromUid;
    if (!fromUid || typeof fromUid !== "string") {
      throw new HttpsError("invalid-argument", "fromUid is required.");
    }

    const requestDoc = await db.collection("users").doc(myUid)
      .collection("friendRequests").doc(fromUid).get();
    if (!requestDoc.exists) {
      throw new HttpsError("not-found", "Friend request not found.");
    }

    const batch = db.batch();
    const now = FieldValue.serverTimestamp();

    batch.set(db.collection("users").doc(myUid).collection("friends").doc(fromUid),
      { friendUid: fromUid, addedAt: now });
    batch.set(db.collection("users").doc(fromUid).collection("friends").doc(myUid),
      { friendUid: myUid, addedAt: now });

    batch.delete(db.collection("users").doc(myUid).collection("friendRequests").doc(fromUid));
    batch.delete(db.collection("users").doc(fromUid).collection("friendRequests").doc(myUid));

    const sorted = [myUid, fromUid].sort();
    const pairId = `${sorted[0]}_${sorted[1]}`;
    batch.set(db.collection("friendships").doc(pairId), {
      userA: sorted[0],
      userB: sorted[1],
      createdAt: now,
      createdBy: myUid,
    });

    await batch.commit();
    return { ok: true };
  }
);

/** Decline a friend request. */
exports.declineFriendRequest = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const myUid = request.auth.uid;
    const fromUid = request.data?.fromUid;
    if (!fromUid || typeof fromUid !== "string") {
      throw new HttpsError("invalid-argument", "fromUid is required.");
    }
    await db.collection("users").doc(myUid)
      .collection("friendRequests").doc(fromUid).delete();
    return { ok: true };
  }
);

/** Remove a friend — deletes both friend links, friendships doc, stale requests. */
exports.removeFriend = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const myUid = request.auth.uid;
    const friendUid = request.data?.friendUid;
    if (!friendUid || typeof friendUid !== "string") {
      throw new HttpsError("invalid-argument", "friendUid is required.");
    }

    const batch = db.batch();
    batch.delete(db.collection("users").doc(myUid).collection("friends").doc(friendUid));
    batch.delete(db.collection("users").doc(friendUid).collection("friends").doc(myUid));
    batch.delete(db.collection("users").doc(myUid).collection("friendRequests").doc(friendUid));
    batch.delete(db.collection("users").doc(friendUid).collection("friendRequests").doc(myUid));

    const sorted = [myUid, friendUid].sort();
    const pairId = `${sorted[0]}_${sorted[1]}`;
    batch.delete(db.collection("friendships").doc(pairId));

    await batch.commit();
    return { ok: true };
  }
);

/**
 * Self-healing reconciliation for a single user's friendships. Repairs the
 * half-written / asymmetric state that earlier remove/re-add churn (or a mixed
 * old-build accept) can leave behind, where one side has the friend record but
 * the other doesn't. Ensures, for every relationship the caller participates in,
 * that BOTH legacy `users/{uid}/friends/{other}` docs AND the canonical
 * `friendships/{pairId}` doc exist. Idempotent and safe to call on app launch.
 */
exports.reconcileFriendships = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const myUid = request.auth.uid;

    // Collect every other-uid the caller is connected to, from all sources.
    const partners = new Set();

    // 1. My own legacy friends subcollection.
    const myFriends = await db.collection("users").doc(myUid)
      .collection("friends").get();
    myFriends.forEach((d) => partners.add(d.id));

    // 2. Canonical friendships docs where I'm a participant.
    const [pairsA, pairsB] = await Promise.all([
      db.collection("friendships").where("userA", "==", myUid).get(),
      db.collection("friendships").where("userB", "==", myUid).get(),
    ]);
    pairsA.forEach((d) => partners.add(d.data().userB));
    pairsB.forEach((d) => partners.add(d.data().userA));

    // 3. Orphaned reciprocals: anyone who lists ME as a friend but whom I may
    //    be missing. Best-effort — if the collection-group index isn't ready
    //    yet, steps 1–2 still reconcile the common cases.
    const reciprocalLinks = new Set();
    let reciprocalKnown = false;
    try {
      const incoming = await db.collectionGroup("friends")
        .where("friendUid", "==", myUid).get();
      incoming.forEach((d) => {
        const owner = d.ref.parent.parent;
        if (owner && owner.id !== myUid) {
          partners.add(owner.id);
          reciprocalLinks.add(owner.id);
        }
      });
      reciprocalKnown = true;
    } catch (err) {
      console.warn(`reconcileFriendships collectionGroup skipped: ${err?.message || err}`);
    }

    partners.delete(myUid);
    if (partners.size === 0) return { ok: true, repaired: 0, writes: 0 };

    // Read-before-write: only create the docs that are actually missing. The
    // reads above already tell us what exists, so a fully-reconciled user (the
    // common case on every app launch) now commits ZERO writes instead of
    // unconditionally rewriting 3 docs per friend every launch. As a bonus this
    // stops the previous merge:true from resetting `createdAt` to now each time.
    const existingFriendships = new Set([
      ...pairsA.docs.map((d) => d.data().userB),
      ...pairsB.docs.map((d) => d.data().userA),
    ]);
    const myFriendLinks = new Set(myFriends.docs.map((d) => d.id));

    const batch = db.batch();
    const now = FieldValue.serverTimestamp();
    let writes = 0;
    for (const other of partners) {
      const sorted = [myUid, other].sort();
      const pairId = `${sorted[0]}_${sorted[1]}`;
      if (!existingFriendships.has(other)) {
        batch.set(db.collection("friendships").doc(pairId), {
          userA: sorted[0],
          userB: sorted[1],
          createdAt: now,
          createdBy: myUid,
        }, { merge: true });
        writes++;
      }
      if (!myFriendLinks.has(other)) {
        batch.set(db.collection("users").doc(myUid).collection("friends").doc(other),
          { friendUid: other, addedAt: now }, { merge: true });
        writes++;
      }
      // The reciprocal link lives on the OTHER user's doc, so we only know it
      // exists when step 3's collection-group read succeeded. If that was
      // skipped (index not ready), write defensively since we can't verify.
      if (!reciprocalKnown || !reciprocalLinks.has(other)) {
        batch.set(db.collection("users").doc(other).collection("friends").doc(myUid),
          { friendUid: myUid, addedAt: now }, { merge: true });
        writes++;
      }
    }
    if (writes > 0) await batch.commit();
    return { ok: true, repaired: partners.size, writes };
  }
);
