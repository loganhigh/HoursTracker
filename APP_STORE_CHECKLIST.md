# App Store Pre-Release Checklist

## Before you submit

1. **App Store Connect**
   - App ID: `6758329353` (configured in `HoursTracker/AppActions.swift`)
   - Privacy Policy URL: `https://hourtracking.online/privacy`
   - Terms URL: `https://hourtracking.online/terms`
   - Support URL: `https://hourtracking.online/support`
   - Marketing URL: `https://hourtracking.online`

2. **Privacy questionnaire (App Store Connect)**
   - Declare: email, user ID, name, work/shift content (linked to user, not used for tracking)
   - Sign in with Apple + Firebase Auth/Firestore for optional cloud sync
   - Push notifications (optional, user-controlled)
   - No ads / no ATT required

3. **Deploy backend before TestFlight**
   ```bash
   .tools/firebase deploy --only firestore:rules --project hour-tracker-1fa55
   cd functions && npm install && firebase deploy --only functions --project hour-tracker-1fa55
   ```

4. **Signing**
   - Archive with **Release** configuration (uses `HoursTrackerRelease.entitlements` → `aps-environment: production`)
   - Debug builds keep `development` APS for local push testing

5. **Export compliance**
   - `ITSAppUsesNonExemptEncryption = NO` — confirm in Connect if prompted

6. **Test on device + TestFlight**
   - Onboarding, add/edit/delete shifts, pay cycle, reports, export
   - Sign in with Apple → cloud sync → friends → leaderboard → activity → friends board
   - Account → Delete account (full cloud removal)
   - Settings → Delete All Data (local only — verify copy is clear)
   - Push notifications with app backgrounded (TestFlight build)
   - Privacy Policy + Terms links open in Settings, Account, side menu

## Already handled in code

- Sign in with Apple + in-app account deletion (`AccountView` → `AccountDeletionService`)
- Privacy Policy + Terms links in Settings, Account, side menu (`AppLegalURLs.swift`)
- Accurate privacy copy (local storage + optional Firebase sync)
- `PrivacyInfo.xcprivacy` manifest with required-reason APIs
- Debug logging gated (`#if DEBUG`, `DebugLog`)
- No ads / no tracking / no ATT
- App icon (1024 light/dark/tinted) + generated launch screen
- Firestore rules for friends-only social content + private `deviceTokens`
- Build **1.9.2 (8)**

## Manual items (cannot automate)

- App Store screenshots for all required device sizes
- App description, keywords, age rating questionnaire
- Restrict Firebase API key in Google Cloud Console (iOS bundle ID)
- Verify `app-ads.txt` on Netlify if AdMob is added later
