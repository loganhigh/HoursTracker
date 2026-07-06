#!/usr/bin/env node
/**
 * Read-only diagnostic: dumps a user's gamification-related docs from
 * Firestore via the REST API, authenticating with the Firebase CLI's
 * stored login (no service account key needed).
 *
 * Usage (from functions/):  node scripts/inspect-user.js <uid>
 */

const fs = require("fs");
const os = require("os");

const PROJECT_ID = "hour-tracker-1fa55";
// Firebase CLI's public OAuth client (embedded in the open-source CLI).
const CLIENT_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi";

async function getAccessToken() {
  const cfgPath = os.homedir() + "/.config/configstore/firebase-tools.json";
  const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
  const refreshToken = cfg.tokens && cfg.tokens.refresh_token;
  if (!refreshToken) throw new Error("No firebase CLI refresh token found");
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
    }),
  });
  if (!res.ok) throw new Error("token exchange failed: " + (await res.text()));
  return (await res.json()).access_token;
}

function flattenValue(v) {
  if (v == null) return null;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("stringValue" in v) return v.stringValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("timestampValue" in v) return v.timestampValue;
  if ("nullValue" in v) return null;
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(flattenValue);
  if ("mapValue" in v) {
    const out = {};
    for (const [k, mv] of Object.entries(v.mapValue.fields || {})) out[k] = flattenValue(mv);
    return out;
  }
  return v;
}

async function getDoc(token, path) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (res.status === 404) return { __missing: true };
  if (!res.ok) throw new Error(`GET ${path} -> ${res.status}: ${await res.text()}`);
  const doc = await res.json();
  const out = { __updateTime: doc.updateTime };
  for (const [k, v] of Object.entries(doc.fields || {})) out[k] = flattenValue(v);
  return out;
}

function pick(obj, keys) {
  const out = {};
  for (const k of keys) if (k in obj) out[k] = obj[k];
  if (obj.__updateTime) out.__updateTime = obj.__updateTime;
  if (obj.__missing) out.__missing = true;
  return out;
}

async function main() {
  const uid = process.argv[2];
  if (!uid) {
    console.error("usage: node scripts/inspect-user.js <uid>");
    process.exit(1);
  }
  const token = await getAccessToken();

  const [userDoc, gamDoc, lifetimeDoc, publicDoc] = await Promise.all([
    getDoc(token, `users/${uid}`),
    getDoc(token, `users/${uid}/gamification/current`),
    getDoc(token, `users/${uid}/stats/lifetime`),
    getDoc(token, `publicProfiles/${uid}`),
  ]);

  console.log("=== users/{uid} (legacy mirror) ===");
  console.log(JSON.stringify(pick(userDoc, [
    "level", "prestige", "totalXP", "totalHours",
    "adminFloorLevel", "adminFloorPrestige", "adminEquippedTitle",
    "statsComputeSeq", "displayName",
  ]), null, 2));

  console.log("\n=== users/{uid}/gamification/current ===");
  console.log(JSON.stringify(pick(gamDoc, [
    "level", "prestige", "totalXP", "adminXPOffset",
    "levelOverride", "prestigeOverride",
    "prestigeXPSnapshots", "prestigeHourSnapshots",
    "highWaterPrestige", "bestStreak", "equippedTitle",
  ]), null, 2));

  console.log("\n=== users/{uid}/stats/lifetime (server-computed) ===");
  console.log(JSON.stringify(pick(lifetimeDoc, [
    "level", "prestige", "totalXP", "totalHours", "badgeCount",
  ]), null, 2));

  console.log("\n=== publicProfiles/{uid} (friends see this) ===");
  console.log(JSON.stringify(pick(publicDoc, [
    "level", "prestige", "totalXP", "totalHours", "displayName",
  ]), null, 2));
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
