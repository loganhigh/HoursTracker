#!/usr/bin/env node
/**
 * One-off: fills photoURL on Board Chat messages (globalChat) that were saved
 * without one. Before abc50e1 the server read publicProfiles.photoURL, which
 * doesn't exist (the field is profilePhotoURL), so every message got "".
 *
 * Authenticates with the Firebase CLI's stored login, like inspect-user.js.
 *
 * Usage (from functions/):
 *   node scripts/backfill-chat-photos.js          # dry run, writes nothing
 *   node scripts/backfill-chat-photos.js --write  # apply
 */

const fs = require("fs");
const os = require("os");

const PROJECT_ID = "hour-tracker-1fa55";
const CLIENT_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const WRITE = process.argv.includes("--write");

async function getAccessToken() {
  const cfg = JSON.parse(fs.readFileSync(os.homedir() + "/.config/configstore/firebase-tools.json", "utf8"));
  const refreshToken = cfg.tokens && cfg.tokens.refresh_token;
  if (!refreshToken) throw new Error("No firebase CLI refresh token found");
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token", refresh_token: refreshToken,
      client_id: CLIENT_ID, client_secret: CLIENT_SECRET,
    }),
  });
  if (!res.ok) throw new Error("token exchange failed: " + (await res.text()));
  return (await res.json()).access_token;
}

async function listAll(token, collection) {
  const docs = [];
  let pageToken = "";
  do {
    const url = `${BASE}/${collection}?pageSize=300${pageToken ? `&pageToken=${pageToken}` : ""}`;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) throw new Error(`list ${collection} -> ${res.status}: ${await res.text()}`);
    const body = await res.json();
    docs.push(...(body.documents || []));
    pageToken = body.nextPageToken || "";
  } while (pageToken);
  return docs;
}

const str = (f) => (f && typeof f.stringValue === "string" ? f.stringValue.trim() : "");

async function main() {
  const token = await getAccessToken();
  const messages = await listAll(token, "globalChat");
  const missing = messages.filter((d) => !str(d.fields?.photoURL));
  const uids = [...new Set(missing.map((d) => str(d.fields?.uid)).filter(Boolean))];

  const photoByUid = {};
  for (const uid of uids) {
    const res = await fetch(`${BASE}/publicProfiles/${uid}`, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) continue;
    const f = (await res.json()).fields || {};
    const url = str(f.profilePhotoURL) || str(f.photoURL);
    if (url) photoByUid[uid] = url;
  }

  const updates = missing.filter((d) => photoByUid[str(d.fields?.uid)]);
  console.log(`${messages.length} messages, ${missing.length} without a photo, ` +
    `${updates.length} fixable (${Object.keys(photoByUid).length}/${uids.length} senders have a photo).`);
  if (!WRITE) { console.log("Dry run. Re-run with --write to apply."); return; }

  // Commit in chunks; updateMask touches only photoURL.
  for (let i = 0; i < updates.length; i += 400) {
    const writes = updates.slice(i, i + 400).map((d) => ({
      update: { name: d.name, fields: { photoURL: { stringValue: photoByUid[str(d.fields.uid)] } } },
      updateMask: { fieldPaths: ["photoURL"] },
      currentDocument: { exists: true },
    }));
    const res = await fetch(`${BASE}:commit`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ writes }),
    });
    if (!res.ok) throw new Error(`commit -> ${res.status}: ${await res.text()}`);
  }
  console.log(`Updated ${updates.length} messages.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
