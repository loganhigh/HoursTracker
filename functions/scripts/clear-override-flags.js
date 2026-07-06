#!/usr/bin/env node
/**
 * One-time repair: remove lingering `levelOverride`/`prestigeOverride` flags
 * from every users/{uid}/gamification/current doc. These flags were meant to
 * be consume-and-cleared by clients; any that stuck around re-apply an old
 * admin level set on every app launch. The offset-based set (adminXPOffset)
 * is left untouched. Auth: Firebase CLI stored login (project owner).
 *
 * Usage (from functions/):  node scripts/clear-override-flags.js
 */

const fs = require("fs");
const os = require("os");

const PROJECT_ID = "hour-tracker-1fa55";
const CLIENT_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

async function getAccessToken() {
  const cfg = JSON.parse(
    fs.readFileSync(os.homedir() + "/.config/configstore/firebase-tools.json", "utf8")
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: cfg.tokens.refresh_token,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
    }),
  });
  if (!res.ok) throw new Error("token exchange failed: " + (await res.text()));
  return (await res.json()).access_token;
}

async function listUserIds(token) {
  const ids = [];
  let pageToken = "";
  do {
    const url = `${BASE}/users?pageSize=300&mask.fieldPaths=__name__${pageToken ? `&pageToken=${pageToken}` : ""}`;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) throw new Error(`list users -> ${res.status}: ${await res.text()}`);
    const body = await res.json();
    for (const doc of body.documents || []) {
      ids.push(doc.name.split("/").pop());
    }
    pageToken = body.nextPageToken || "";
  } while (pageToken);
  return ids;
}

async function main() {
  const token = await getAccessToken();
  const uids = await listUserIds(token);
  console.log(`scanning ${uids.length} users…`);

  let flagged = 0;
  for (const uid of uids) {
    const path = `users/${uid}/gamification/current`;
    const res = await fetch(`${BASE}/${path}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 404) continue;
    if (!res.ok) {
      console.error(`  ${uid}: read failed ${res.status}`);
      continue;
    }
    const doc = await res.json();
    const f = doc.fields || {};
    const hasLevel = "levelOverride" in f;
    const hasPrestige = "prestigeOverride" in f;
    if (!hasLevel && !hasPrestige) continue;

    flagged += 1;
    const lv = hasLevel ? JSON.stringify(f.levelOverride) : "-";
    const pv = hasPrestige ? JSON.stringify(f.prestigeOverride) : "-";
    console.log(`  ${uid}: levelOverride=${lv} prestigeOverride=${pv} -> clearing`);

    // PATCH with the fields in updateMask but absent from the body deletes
    // them; currentDocument.exists guards against creating an empty doc.
    const mask = ["levelOverride", "prestigeOverride"]
      .map((k) => `updateMask.fieldPaths=${k}`)
      .join("&");
    const patch = await fetch(
      `${BASE}/${path}?${mask}&currentDocument.exists=true`,
      {
        method: "PATCH",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ fields: {} }),
      }
    );
    if (!patch.ok) {
      console.error(`  ${uid}: clear FAILED ${patch.status}: ${await patch.text()}`);
    }
  }
  console.log(`done — cleared flags on ${flagged} user(s)`);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
