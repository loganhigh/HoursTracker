/**
 * Hour Tracker — friend shift push notifications.
 */

const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { recomputeUserStats } = require("./src/stats/recompute");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
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

    const mutualFriendUids = await getMutualFriendUids(authorUid);
    if (mutualFriendUids.length === 0) return;

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
      await recomputeUserStats(db, uid, { beforeEntry, afterEntry });
    } catch (err) {
      console.error(`recomputeUserStats failed uid=${uid}:`, err?.message || err);
      throw err;
    }
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
