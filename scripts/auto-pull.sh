#!/usr/bin/env bash
#
# Watches the current branch and pulls new commits as they land, so you never
# have to type `git pull` again. Run it once in a spare Terminal tab and leave
# it there; Ctrl-C stops it.
#
#   ./scripts/auto-pull.sh            # check every 20s (default)
#   ./scripts/auto-pull.sh 60         # check every 60s
#
# Xcode picks up changed files on disk on its own, and this project uses
# synchronized folders, so new files appear in the navigator without any
# project edit. In practice: the code just updates while you work.
#
# It refuses to touch anything when you have uncommitted edits — losing your
# work to a background process would be far worse than typing a command.

set -uo pipefail

INTERVAL="${1:-20}"

cd "$(dirname "$0")/.." || exit 1

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "Not a git repository — run this from inside your HoursTracker folder."
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "Watching origin/$BRANCH every ${INTERVAL}s. Press Ctrl-C to stop."
echo

while true; do
  # Network hiccups shouldn't kill the watcher.
  if ! git fetch --quiet origin "$BRANCH" 2>/dev/null; then
    sleep "$INTERVAL"
    continue
  fi

  LOCAL="$(git rev-parse HEAD 2>/dev/null)"
  REMOTE="$(git rev-parse "origin/$BRANCH" 2>/dev/null || echo "$LOCAL")"

  if [ "$LOCAL" != "$REMOTE" ]; then
    if [ -n "$(git status --porcelain)" ]; then
      echo "[$(date '+%H:%M:%S')] New commits are waiting, but you have uncommitted"
      echo "                changes. Not pulling — commit or stash them first."
    else
      COUNT="$(git rev-list --count HEAD.."origin/$BRANCH")"
      if git merge --ff-only "origin/$BRANCH" --quiet 2>/dev/null; then
        echo "[$(date '+%H:%M:%S')] Pulled $COUNT new commit(s):"
        git log --oneline -n "$COUNT" | sed 's/^/                /'
        echo
      else
        echo "[$(date '+%H:%M:%S')] Couldn't fast-forward — your branch has diverged."
        echo "                Left it alone; sort it out manually."
      fi
    fi
  fi

  sleep "$INTERVAL"
done
