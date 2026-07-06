# Widget Xcode Setup - Quick Guide

The widget code is ready! Just need to configure file targets in Xcode.

## ✅ Files Already Created

Widget target files:
- ✅ HoursTrackerWidget.swift (replaced Xcode template)
- ✅ HoursTrackerLockScreenWidget.swift 
- ✅ HoursTrackerWidgetBundle.swift (updated)
- ✅ HoursTrackerWidget.entitlements
- ✅ AppIntent.swift (deleted - not needed)

Shared data:
- ✅ WidgetDataManager.swift (in main app folder)

## 🔧 Required Steps in Xcode

### Step 1: Add Shared Files to Widget Target

You need to add these **3 files** to the **HoursTrackerWidget** target:

1. **WidgetDataManager.swift**
   - Location: `HoursTracker/WidgetDataManager.swift`
   - Action: Select file → File Inspector → Check ✅ **HoursTrackerWidget** target

2. **WorkEntry.swift**
   - Location: `HoursTracker/WorkEntry.swift`
   - Action: Select file → File Inspector → Check ✅ **HoursTrackerWidget** target

3. **PaySettingsAndSettingsView.swift** (contains PaySettings struct)
   - Location: `HoursTracker/PaySettingsAndSettingsView.swift`
   - Action: Select file → File Inspector → Check ✅ **HoursTrackerWidget** target

**How to add files to target:**
1. Click on the file in Project Navigator
2. Open **File Inspector** (⌥⌘1 or View → Inspectors → File)
3. Under **Target Membership**, check the box next to **HoursTrackerWidget**

### Step 2: Update App Group ID

In **WidgetDataManager.swift** (line 29), replace:
```swift
private let appGroupID = "group.com.yourname.HoursTracker"
```

With your own App Group ID (use your Team ID or name):
```swift
private let appGroupID = "group.com.YOURNAME.HoursTracker"
```

Example: `group.com.loganhigh.HoursTracker`

### Step 3: Enable App Groups

#### For Main App (HoursTracker target):
1. Select project → **HoursTracker** target
2. **Signing & Capabilities** tab
3. Click **+ Capability** → Add **App Groups**
4. Click **+** to add new group
5. Enter: `group.com.YOURNAME.HoursTracker` (match what you used above)
6. Check the box next to it

#### For Widget (HoursTrackerWidget target):
1. Select project → **HoursTrackerWidget** target
2. **Signing & Capabilities** tab
3. Click **+ Capability** → Add **App Groups**
4. Click **+** to add new group
5. Enter the **SAME** App Group ID: `group.com.YOURNAME.HoursTracker`
6. Check the box next to it

⚠️ **Important**: Both targets MUST use the exact same App Group ID!

### Step 4: Update Entitlements (Should be automatic)

If App Groups don't appear in entitlements files, manually add:

**HoursTracker.entitlements:**
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.YOURNAME.HoursTracker</string>
</array>
```

**HoursTrackerWidget.entitlements:**
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.YOURNAME.HoursTracker</string>
</array>
```

### Step 5: Build and Test

1. **Clean Build Folder**: Product → Clean Build Folder (⇧⌘K)
2. **Build**: Product → Build (⌘B)
3. Fix any remaining errors (should only be missing target membership)
4. **Run** the main app (⌘R)
5. Add widget from home screen:
   - Long press home screen → + button → Search "Hours Tracker"

## 🐛 Common Issues

### "Cannot find 'WidgetData' in scope"
→ Add `WidgetDataManager.swift` to widget target (Step 1)

### "Cannot find 'WorkEntry' in scope"  
→ Add `WorkEntry.swift` to widget target (Step 1)

### "Cannot find 'PaySettings' in scope"
→ Add `PaySettingsAndSettingsView.swift` to widget target (Step 1)

### Widget shows blank/no data
→ Check App Group IDs match in both targets and in code

### Build errors about App Groups
→ Make sure App Groups capability is enabled for BOTH targets

## 🎉 Success Indicators

When everything works:
- ✅ No build errors
- ✅ Widget appears in widget gallery
- ✅ Widget shows your actual hours data
- ✅ Widget updates when you add entries
- ✅ Lock screen widgets available (iOS 16+)

## 📱 Available Widgets

After setup, you'll have:
- **Small Widget** - Circular progress with hours this cheque
- **Medium Widget** - Full dashboard with today, cheque, month, streak
- **Lock Screen Circular** - Compact gauge
- **Lock Screen Rectangular** - All three metrics
- **Lock Screen Inline** - Today's hours + streak

All widgets update every 15 minutes and when app backgrounds!
