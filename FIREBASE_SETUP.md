# Firebase setup (Hour Tracker)

Complete these steps once in Firebase Console and Xcode before cloud sync and Friends will work.

## Quick setup (recommended)

If you have Node.js installed (`node` + `npm`):

```bash
cd "/Users/loganhigh/Desktop/HoursTracker 2"
npm install -g firebase-tools
./scripts/setup-firebase.sh YOUR_FIREBASE_PROJECT_ID
```

That script will:

- Log you into Firebase
- Register the iOS app (`com.app.HourTracker`)
- Download `HoursTracker/GoogleService-Info.plist`
- Create Firestore (if missing)
- Deploy `firestore.rules`

You still must **enable Apple** in the console (step 4 below) — the CLI cannot do that yet.

---

## 1. Firebase Console (manual)

1. Open [Firebase Console](https://console.firebase.google.com/) and create a project (or use your new one).
2. **Add app → iOS**
   - Bundle ID: `com.app.HourTracker`
   - Download **GoogleService-Info.plist**
3. Drag `GoogleService-Info.plist` into the **HoursTracker** folder in Xcode (copy if prompted).
4. **Build → Authentication → Sign-in method** — enable:
   - **Apple**
   - **Google** (add your iOS bundle ID `com.app.HourTracker` if prompted)
   - **Email/Password**
5. **Build → Firestore Database → Create database** (production mode is fine; deploy rules below).

## 2. Xcode

1. **File → Add Package Dependencies**
   - URL: `https://github.com/firebase/firebase-ios-sdk`
   - Version: **11.x** (Up to Next Major)
   - Add to **HoursTracker** target only:
     - `FirebaseAuth`
     - `FirebaseFirestore`
     - `FirebaseMessaging`
     - `GoogleSignIn` from `https://github.com/google/GoogleSignIn-iOS`
     - `FirebaseCore` (pulled in automatically if needed)
2. **Signing & Capabilities** on HoursTracker target:
   - **+ Capability → Sign In with Apple** (entitlements file already includes `com.apple.developer.applesignin`)
   - **+ Capability → Push Notifications**

## 3. Firestore security rules

In Firebase Console → Firestore → Rules, paste the contents of [`firestore.rules`](firestore.rules) and **Publish**.

## 4. Firestore indexes (if prompted)

Adding friends by email uses:

- Collection: `users`
- Field: `lookupEmail`

If the console asks for a composite index when sending a friend request, create the suggested index.

## 5. Verify

1. Run the app on a device or simulator (Sign in with Apple works best on a **real device**).
2. Onboarding or Account → sign in with **Apple**, **Google**, or **email/password**
3. Log a shift → check Firestore `users/{uid}/entries`

## 6. Friend shift push notifications (FCM)

Background alerts like **"Joey worked 8h today"** use Firebase Cloud Messaging + Cloud Functions.

### One-time Firebase Console setup

1. **Project settings → Cloud Messaging → Apple app configuration**
   - Upload your **APNs Authentication Key** (.p8) from [Apple Developer → Keys](https://developer.apple.com/account/resources/authkeys/list), or use an APNs certificate.
2. **Upgrade to Blaze (pay-as-you-go)** — Cloud Functions require it (free tier covers light usage).
3. In Xcode → **HoursTracker target → Signing & Capabilities → + Push Notifications**.

### Deploy the Cloud Function

```bash
chmod +x scripts/deploy-functions.sh
./scripts/deploy-functions.sh hour-tracker-1fa55
```

This deploys `notifyFriendsOnShiftLogged`, which fires when a friend writes a `shiftLogged` activity event.

### How it works

1. User logs a shift → app writes `users/{uid}/activity/shift_{entryId}` (requires **Post to activity feed** ON).
2. Cloud Function notifies mutual friends who have **Friend shift alerts** enabled.
3. Each device registers an FCM token at `users/{uid}.fcmTokens.{deviceId}` on sign-in.

### Test on a real device

Push does not work on the iOS Simulator. Use two signed-in accounts that are friends, both with notifications allowed.

---

## Notes

- Without `GoogleService-Info.plist`, the app still runs locally; Firebase is skipped with a debug warning.
- **Hide My Email**: friends must use the relay address shown in Account, or set a findable email manually.
- First sign-in on a device uploads local entries if the cloud is empty.
- Signing in on a second device with existing local data shows **Replace local data?** before applying cloud entries.
