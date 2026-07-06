---
name: "Run HoursTracker in iOS Simulator"
description: "Build, install, launch, and screenshot the HoursTracker iOS app in the Simulator to runtime-smoke-test Swift changes beyond a plain xcodebuild. Use when asked to run, launch, or screenshot the app, or to confirm a Swift change launches and renders without crashing. Documents the working build→install→launch→observe loop and the known limits (no idb tap-driving, sign-in-gated onboarding, sandboxed simctl privacy)."
---

# Run HoursTracker in iOS Simulator

## What This Skill Does
Runs the actual HoursTracker app in the iOS Simulator so you can verify a Swift
change at **runtime** (launches, renders, doesn't crash) — not just that it
compiles. The build → install → launch → screenshot loop is proven to work in
this repo. Interactive tap-driving is **not** available here (see Limits).

Use it as a smoke test after editing any Swift under `HoursTracker/`.

## Prerequisites
- macOS with Xcode (verified on Xcode 26.2) — `xcodebuild`, `xcrun simctl`.
- Scheme: `HoursTracker`. Main app bundle id: `com.app.HourTracker`.
- Swift Package Manager deps (Firebase 12.13.0 etc.) resolve automatically.

## Quick Start (copy/paste)
```bash
cd "<repo root>"                       # dir containing HoursTracker.xcodeproj
DD="$(mktemp -d)/dd"                   # or a scratchpad path; keep off the repo

# Pick the first available booted-or-bootable iPhone simulator
SIM=$(xcrun simctl list devices available | grep -m1 -oE '[0-9A-F-]{36}')

# 1) Build for the simulator (no signing needed)
xcodebuild -project HoursTracker.xcodeproj -scheme HoursTracker \
  -destination "id=$SIM" -configuration Debug -derivedDataPath "$DD" \
  build CODE_SIGNING_ALLOWED=NO

# 2) Boot, install, launch
xcrun simctl bootstatus "$SIM" -b
xcrun simctl install "$SIM" "$DD/Build/Products/Debug-iphonesimulator/HoursTracker.app"
xcrun simctl launch "$SIM" com.app.HourTracker

# 3) Observe — screenshot, then LOOK at it (a blank frame = launch failure)
xcrun simctl io "$SIM" screenshot out.png
```
Then Read `out.png`. A successful launch shows the onboarding flow ("Hour
Tracker", a page-dots row, a "Continue" button). Confirm the process is alive:
```bash
xcrun simctl spawn "$SIM" launchctl list | grep -i HourTracker   # PID present = running
```

## Notes that save time
- **Pick a concrete device** if you prefer: `xcrun simctl list devices available`
  then use that UUID for `$SIM`. iPhone 17 Pro works well.
- **Rebuild-relaunch loop** after an edit: rerun steps 1–3. `terminate` first for
  a clean relaunch: `xcrun simctl terminate "$SIM" com.app.HourTracker`.
- **Logs**: `xcrun simctl spawn "$SIM" log stream --level=debug \
  --predicate 'processImagePath CONTAINS "HoursTracker"'` (run in background;
  the app logs sparsely at launch, so give it activity to see output).
- A plain compile check (no sim) is:
  `xcodebuild -project HoursTracker.xcodeproj -scheme HoursTracker \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`.

## Limits (what this loop CANNOT do here — be honest about it)
- **No tap/type driving.** Navigating multi-screen flows needs `idb`
  (`idb ui tap`/`text`), which requires `idb_companion` via Homebrew. If `brew`
  and `idb` are absent, you can build/launch/screenshot but cannot tap past a
  screen (e.g. the notification-permission dialog on onboarding). Install path:
  `brew install idb-companion && pip install fb-idb`.
- **Onboarding requires sign-in** (Google/Apple), which can't be completed in a
  clean simulator — so you cannot reach the main app / log a shift this way
  without real auth. Deep flows (friends, cloud sync, per-account state) need a
  real device or a dev environment with test accounts.
- **`xcrun simctl privacy … grant` is sandbox-blocked** in some CI/agent shells
  ("Operation not permitted"), so you can't pre-grant notifications to clear
  that dialog.

## When to use vs. not
- **Use** to confirm a Swift edit builds AND launches AND renders (catches
  crashes, missing assets, startup-path regressions xcodebuild alone misses).
- **Don't rely on it** to validate friend/sync/re-render behavior that lives
  behind sign-in — that needs a real device + accounts, not this loop.
