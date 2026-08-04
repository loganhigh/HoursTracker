#!/usr/bin/env node
/**
 * One-shot repair: writes a fully self-consistent progression state for a
 * user across ALL four progression docs (gamification/current, users/{uid}
 * legacy mirror, stats/lifetime, publicProfiles). Mirrors the server's
 * applyAdminProgressionSet offset math, so shifts keep earning XP after.
 *
 * Fixes accounts whose docs contradict each other (e.g. highWaterPrestige
 * above the actual prestige, leftover adminXPOffset from an old admin set),
 * which makes the client flap between levels on every launch.
 *
 * Usage (from functions/):
 *   node scripts/repair-user-progression.js <uid> <targetLevel> <targetPrestige>
 */

const fs = require("fs");
const os = require("os");

const PROJECT_ID = "hour-tracker-1fa55";
// Firebase CLI's public OAuth client (embedded in the open-source CLI).
const CLIENT_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi";

const MAX_LEVEL = 25;

function xpRequiredForLevel(level) {
  const l = Math.max(1, level);
  return Math.floor(900 + (l - 1) * 180 + Math.pow(l - 1, 1.22) * 18);
}

function totalXPForFullPrestigeRun() {
  let total = 0;
  for (let l = 1; l <= MAX_LEVEL; l++) total += xpRequiredForLevel(l);
  return total;
}

function buildSnapshotsForPrestige(prestige) {
  const runXP = totalXPForFullPrestigeRun();
  const snaps = [];
  let cumulative = 0;
  for (let i = 0; i < prestige; i++) {
    cumulative += runXP;
    snaps.push(cumulative);
  }
  return snaps;
}

function totalXPAtLevelStart(level, prestige) {
  let total = prestige * totalXPForFullPrestigeRun();
  for (let l = 1; l < level; l++) total += xpRequiredForLevel(l);
  return total;
}

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

function docUrl(path, maskFields) {
  const mask = maskFields
    .map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`)
    .join("&");
  return `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}?${mask}`;
}

async function getDoc(token, path) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`GET ${path} -> ${res.status}: ${await res.text()}`);
  return res.json();
}

function flat(v) {
  if (v == null) return null;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  return null;
}

async function patchDoc(token, path, maskFields, fields) {
  const res = await fetch(docUrl(path, maskFields), {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) throw new Error(`PATCH ${path} -> ${res.status}: ${await res.text()}`);
  console.log(`patched ${path}`);
}

const int = (n) => ({ integerValue: String(Math.round(n)) });
const dbl = (n) => ({ doubleValue: n });
const intArray = (arr) => ({
  arrayValue: { values: arr.map((n) => int(n)) },
});

async function main() {
  const [uid, levelArg, prestigeArg] = process.argv.slice(2);
  const targetLevel = Number(levelArg);
  const targetPrestige = Number(prestigeArg);
  if (!uid || !Number.isInteger(targetLevel) || !Number.isInteger(targetPrestige)) {
    console.error("usage: node scripts/repair-user-progression.js <uid> <targetLevel> <targetPrestige>");
    process.exit(1);
  }
  if (targetLevel < 1 || targetLevel > MAX_LEVEL || targetPrestige < 0 || targetPrestige > 10) {
    console.error(`level must be 1-${MAX_LEVEL}, prestige 0-10`);
    process.exit(1);
  }

  const token = await getAccessToken();

  // Shift-derived XP = current synced totalXP minus any existing admin offset.
  const gamDoc = await getDoc(token, `users/${uid}/gamification/current`);
  if (!gamDoc) throw new Error("gamification/current doc missing for " + uid);
  const g = gamDoc.fields || {};
  const syncedTotal = flat(g.totalXP) || 0;
  const existingOffset = flat(g.adminXPOffset) || 0;
  const entryXP = syncedTotal - existingOffset;

  const snapshots = buildSnapshotsForPrestige(targetPrestige);
  const targetStart = totalXPAtLevelStart(targetLevel, targetPrestige);
  const newOffset = targetStart - entryXP;
  const newTotal = targetStart;

  // Hour snapshots must have one entry per prestige and each must be at or
  // below the user's real lifetime hours, or the client's hour-rollback
  // logic would strip the prestige right back off.
  const lifetimeDoc = await getDoc(token, `users/${uid}/stats/lifetime`);
  const totalHours = flat((lifetimeDoc?.fields || {}).totalHours) || 0;
  const hourSnaps = [];
  for (let i = 0; i < targetPrestige; i++) {
    hourSnaps.push((totalHours * (i + 1)) / (targetPrestige + 1));
  }

  console.log({ uid, targetLevel, targetPrestige, entryXP, newOffset, newTotal, snapshots, hourSnaps });

  await patchDoc(
    token,
    `users/${uid}/gamification/current`,
    [
      "prestige", "prestigeFloor", "highWaterPrestige",
      "prestigeXPSnapshots", "prestigeHourSnapshots",
      "adminXPOffset", "totalXP", "level",
      "levelOverride", "prestigeOverride",
    ],
    // levelOverride / prestigeOverride omitted from fields -> deleted by mask.
    {
      prestige: int(targetPrestige),
      prestigeFloor: int(targetPrestige),
      highWaterPrestige: int(targetPrestige),
      prestigeXPSnapshots: intArray(snapshots),
      prestigeHourSnapshots: { arrayValue: { values: hourSnaps.map((h) => dbl(h)) } },
      adminXPOffset: int(newOffset),
      totalXP: int(newTotal),
      level: int(targetLevel),
    }
  );

  await patchDoc(
    token,
    `users/${uid}`,
    ["level", "prestige", "totalXP", "adminFloorLevel", "adminFloorPrestige"],
    // adminFloor* omitted -> deleted.
    {
      level: int(targetLevel),
      prestige: int(targetPrestige),
      totalXP: int(newTotal),
    }
  );

  await patchDoc(
    token,
    `users/${uid}/stats/lifetime`,
    ["level", "prestige", "totalXP"],
    { level: int(targetLevel), prestige: int(targetPrestige), totalXP: int(newTotal) }
  );

  await patchDoc(
    token,
    `publicProfiles/${uid}`,
    ["level", "prestige", "totalXP"],
    { level: int(targetLevel), prestige: int(targetPrestige), totalXP: int(newTotal) }
  );

  console.log("done — all four docs now agree.");
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
