# Hour Tracker 1.9.1 — App Store Release Notes

## What's New (paste into App Store Connect)

**Friends & sync improvements**

- Fixed an issue where only one friend could see the other's hours after connecting
- You can now remove friends (swipe left or long-press in the Friends list)
- Improved cross-device sync — your level, hours, and settings stay up to date when signed in on multiple devices
- Data refreshes automatically when you open the app

---

## Promotional Text (optional, 170 chars max)

Friends sync better, remove friends anytime, and your hours & level stay in sync across all your devices.

---

## Full Release Notes (for website / support page)

### Version 1.9.1

**Friends**
- Both users now see each other's hours after sending or accepting a friend request
- New: remove a friend by swiping left or using the context menu in Friends
- Friend stats refresh more reliably from the cloud

**Cloud sync**
- Sign in with Apple on a second device and your data pulls from the cloud on launch and when returning to the app
- Pay settings sync live across devices, not just work entries
- Level and XP recalculate from synced entries so progress matches everywhere

**Before submitting to App Store**
1. Deploy updated Firestore rules: `firebase deploy --only firestore:rules`
2. Archive with build **6** / version **1.9.1**
3. Test friends (both directions) and multi-device sync on TestFlight before release
