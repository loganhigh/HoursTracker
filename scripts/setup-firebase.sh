#!/usr/bin/env bash
# Hour Tracker — one-shot Firebase setup (Console steps automated via CLI where possible).
#
# Prerequisites (run once on your Mac):
#   brew install node          # or install Node from https://nodejs.org
#   npm install -g firebase-tools
#
# Usage:
#   cd "/Users/loganhigh/Desktop/HoursTracker 2"
#   chmod +x scripts/setup-firebase.sh
#   ./scripts/setup-firebase.sh YOUR_FIREBASE_PROJECT_ID
#
# Example:
#   ./scripts/setup-firebase.sh hour-tracker-abc123

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT_ID="${1:-}"
BUNDLE_ID="com.app.HourTracker"
APP_NAME="Hour Tracker"
PLIST_PATH="HoursTracker/GoogleService-Info.plist"
FIRESTORE_LOCATION="${FIRESTORE_LOCATION:-nam5}"

if [[ -z "$PROJECT_ID" ]]; then
  echo "Usage: $0 <firebase-project-id>"
  echo ""
  echo "Find your Project ID in Firebase Console → Project settings → General."
  exit 1
fi

if ! command -v firebase >/dev/null 2>&1; then
  echo "firebase CLI not found. Install with: npm install -g firebase-tools"
  exit 1
fi

echo "→ Logging in (browser opens if needed)…"
firebase login

echo "→ Using project: $PROJECT_ID"
cp -n .firebaserc.example .firebaserc 2>/dev/null || true
# shellcheck disable=SC2016
node -e "
const fs=require('fs');
const p='.firebaserc';
const j=fs.existsSync(p)?JSON.parse(fs.readFileSync(p,'utf8')):{projects:{}};
j.projects=j.projects||{};
j.projects.default=process.argv[1];
fs.writeFileSync(p, JSON.stringify(j,null,2)+'\n');
" "$PROJECT_ID"

firebase use "$PROJECT_ID"

echo "→ Registering iOS app ($BUNDLE_ID) if needed…"
IOS_APP_ID=""
EXISTING="$(firebase apps:list IOS --project "$PROJECT_ID" 2>/dev/null || true)"
if echo "$EXISTING" | grep -q "$BUNDLE_ID"; then
  IOS_APP_ID="$(firebase apps:list IOS --project "$PROJECT_ID" --json | node -e "
    const d=JSON.parse(require('fs').readFileSync(0,'utf8'));
    const app=(d.result||[]).find(a=>a.platform==='IOS' && (a.namespace||'').includes('$BUNDLE_ID'));
    if(app) console.log(app.appId);
  ")"
  echo "   Found existing iOS app: $IOS_APP_ID"
else
  IOS_APP_ID="$(firebase apps:create IOS "$BUNDLE_ID" "$APP_NAME" --project "$PROJECT_ID" --json | node -e "
    const d=JSON.parse(require('fs').readFileSync(0,'utf8'));
    console.log(d.appId||'');
  ")"
  echo "   Created iOS app: $IOS_APP_ID"
fi

if [[ -z "$IOS_APP_ID" ]]; then
  echo "Could not resolve iOS App ID. Download GoogleService-Info.plist manually from Firebase Console."
else
  echo "→ Downloading GoogleService-Info.plist → $PLIST_PATH"
  firebase apps:sdkconfig IOS "$IOS_APP_ID" --project "$PROJECT_ID" > "$PLIST_PATH"
  echo "   Saved $PLIST_PATH"
fi

echo "→ Creating Firestore database (skipped if it already exists)…"
firebase firestore:databases:create "(default)" --location "$FIRESTORE_LOCATION" --project "$PROJECT_ID" 2>/dev/null || \
  echo "   (database may already exist — continuing)"

echo "→ Deploying Firestore security rules…"
firebase deploy --only firestore:rules --project "$PROJECT_ID"

cat <<'MANUAL'

✅ Automated steps finished.

Still do these in Firebase Console (CLI cannot enable Apple sign-in yet):

1. Authentication → Sign-in method → Apple → Enable → Save
2. Confirm GoogleService-Info.plist appears in Xcode under HoursTracker/
3. Xcode → HoursTracker target → Signing & Capabilities → Sign In with Apple (entitlements already in repo)

Then run the app, open Account → Sign in with Apple, and log a test shift.

MANUAL
