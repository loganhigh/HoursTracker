#!/usr/bin/env node
/**
 * One-time cleanup: delete stale `_fcmDedup` idempotency markers.
 *
 * Background: `notifyFriendsOnShiftLogged` writes one `_fcmDedup/{shift_...}`
 * doc per shift-notification event and never deletes it. Newer docs also carry
 * an `expiresAt` field so a Firestore TTL policy can sweep them — but docs
 * written before that change have only `sentAt`, and a TTL policy ignores docs
 * with no `expiresAt`, so the old backlog would live forever. These markers are
 * spent once their event is a few minutes old, so deleting old ones is safe.
 *
 * Deletes every `_fcmDedup` doc whose `sentAt` is older than the cutoff (or has
 * no `sentAt` at all). New markers (recent, and TTL-managed) are left alone.
 * Auth: Firebase CLI stored login (project owner) — same as the other scripts.
 *
 * Usage (from functions/):
 *   node scripts/delete-stale-fcmdedup.js            # delete, cutoff = 2 days
 *   node scripts/delete-stale-fcmdedup.js --dry-run  # count only, delete nothing
 *   node scripts/delete-stale-fcmdedup.js 7          # custom cutoff in days
 */

const fs = require("fs");
const os = require("os");

const PROJECT_ID = "hour-tracker-1fa55";
const CLIENT_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi";
const DB = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const COLLECTION = "_fcmDedup";

const DRY_RUN = process.argv.includes("--dry-run");
const cutoffDaysArg = process.argv.find((a) => /^\d+(\.\d+)?$/.test(a));
const CUTOFF_DAYS = cutoffDaysArg ? Number(cutoffDaysArg) : 2;
const CUTOFF_MS = Date.now() - CUTOFF_DAYS * 24 * 60 * 60 * 1000;

// Resolve the refresh token for the account that should be used. The default
// firebase-tools account may not have Firestore access on this project; the
// per-directory active account (set via `firebase login:use`) usually does.
// Order: $FIREBASE_ACCOUNT > this directory's activeAccounts entry > default.
function resolveRefreshToken(cfg) {
  const cwd = process.cwd();
  let target = process.env.FIREBASE_ACCOUNT;
  if (!target && cfg.activeAccounts) {
    const dir = Object.keys(cfg.activeAccounts)
      .filter((d) => cwd === d || cwd.startsWith(d + "/"))
      .sort((a, b) => b.length - a.length)[0];
    if (dir) target = cfg.activeAccounts[dir];
  }
  if (!target) target = cfg.user && cfg.user.email;

  const tokenFor = (email) => {
    if (cfg.user && cfg.user.email === email && cfg.tokens) return cfg.tokens.refresh_token;
    const acct = (cfg.additionalAccounts || []).find((a) => a.user && a.user.email === email);
    return acct && acct.tokens && acct.tokens.refresh_token;
  };

  const rt = tokenFor(target);
  if (!rt) {
    throw new Error(
      `No stored Firebase CLI token for account "${target}". ` +
        `Run \`firebase login:use <email>\` in this directory, or set FIREBASE_ACCOUNT.`
    );
  }
  console.log(`Using Firebase account: ${target}`);
  return rt;
}

async function getAccessToken() {
  const cfg = JSON.parse(
    fs.readFileSync(os.homedir() + "/.config/configstore/firebase-tools.json", "utf8")
  );
  const refreshToken = resolveRefreshToken(cfg);
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

// Collect ids of stale docs (sentAt older than cutoff, or missing sentAt).
async function collectStaleIds(token) {
  const stale = [];
  let scanned = 0;
  let pageToken = "";
  do {
    const url =
      `${DB}/${COLLECTION}?pageSize=300&mask.fieldPaths=sentAt` +
      (pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : "");
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) throw new Error(`list ${COLLECTION} -> ${res.status}: ${await res.text()}`);
    const body = await res.json();
    for (const doc of body.documents || []) {
      scanned++;
      const id = doc.name.split("/").pop();
      const ts = doc.fields && doc.fields.sentAt && doc.fields.sentAt.timestampValue;
      const sentMs = ts ? Date.parse(ts) : NaN;
      if (!Number.isFinite(sentMs) || sentMs < CUTOFF_MS) {
        stale.push(id);
      }
    }
    pageToken = body.nextPageToken || "";
  } while (pageToken);
  return { stale, scanned };
}

async function batchDelete(token, ids) {
  // Firestore :batchWrite accepts up to 500 writes per call.
  const CHUNK = 300;
  let deleted = 0;
  for (let i = 0; i < ids.length; i += CHUNK) {
    const chunk = ids.slice(i, i + CHUNK);
    const writes = chunk.map((id) => ({
      delete: `projects/${PROJECT_ID}/databases/(default)/documents/${COLLECTION}/${id}`,
    }));
    const res = await fetch(`${DB}:batchWrite`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ writes }),
    });
    if (!res.ok) throw new Error(`batchWrite -> ${res.status}: ${await res.text()}`);
    deleted += chunk.length;
    console.log(`  deleted ${deleted}/${ids.length}…`);
  }
  return deleted;
}

async function main() {
  console.log(
    `${DRY_RUN ? "[DRY RUN] " : ""}Cleaning ${COLLECTION} older than ${CUTOFF_DAYS} day(s)…`
  );
  const token = await getAccessToken();
  const { stale, scanned } = await collectStaleIds(token);
  console.log(`Scanned ${scanned} markers; ${stale.length} are stale.`);

  if (stale.length === 0) {
    console.log("Nothing to delete.");
    return;
  }
  if (DRY_RUN) {
    console.log(`[DRY RUN] Would delete ${stale.length} docs. Re-run without --dry-run to apply.`);
    return;
  }
  const deleted = await batchDelete(token, stale);
  console.log(`Done. Deleted ${deleted} stale ${COLLECTION} markers.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
