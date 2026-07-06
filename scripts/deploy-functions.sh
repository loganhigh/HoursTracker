#!/usr/bin/env bash
# Deploy Cloud Functions for friend shift push notifications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FIREBASE="$ROOT/.tools/firebase"
PROJECT_ID="${1:-hour-tracker-1fa55}"

if [[ ! -x "$FIREBASE" ]]; then
  echo "Firebase CLI not found at $FIREBASE"
  echo "Run: mkdir -p .tools && curl -sL https://firebase.tools/bin/macos/latest -o .tools/firebase && chmod +x .tools/firebase"
  exit 1
fi

if ! "$FIREBASE" login:list 2>/dev/null | grep -q "@"; then
  echo "Sign in to Firebase (browser will open)..."
  "$FIREBASE" login
fi

echo "Installing function dependencies..."
(cd functions && npm install --silent)

echo "Deploying Cloud Functions to ${PROJECT_ID}..."
"$FIREBASE" deploy --only functions --project "${PROJECT_ID}"
echo "Cloud Functions deployed."
