# Widget Setup Instructions

All widget code files have been created! Follow these steps to add widgets to your Hours Tracker app.

## 📋 Step 1: Create Widget Extension in Xcode

1. Open `HoursTracker.xcodeproj` in Xcode
2. Go to **File > New > Target**
3. Select **Widget Extension** (under iOS section)
4. Click **Next**
5. Configure the widget:
   - **Product Name**: `HoursTrackerWidget`
   - **Team**: Select your development team
   - **Language**: Swift
   - **Include Configuration Intent**: **Uncheck this** (we don't need it)
6. Click **Finish**
7. When prompted "Activate HoursTrackerWidget scheme?", click **Activate**

## 📦 Step 2: Add Widget Files to Target

The following files have been created in your project. You need to add them to the widget target:

### Widget Extension Files (Add to Widget Target Only)
Located in `HoursTrackerWidget/` folder:
- ✅ `HoursTrackerWidget.swift` - Main home screen widgets
- ✅ `HoursTrackerLockScreenWidget.swift` - Lock screen widgets
- ✅ `HoursTrackerWidgetBundle.swift` - Widget bundle configuration
- ✅ `HoursTrackerWidget.entitlements` - Widget entitlements

### Shared Files (Add to BOTH App and Widget Targets)
Located in `HoursTracker/` folder:
- ✅ `WidgetDataManager.swift` - Data sharing between app and widget
- ✅ `WorkEntry.swift` - Already exists, add to widget target
- ✅ `PaySettings.swift` - Already exists, add to widget target (via PaySettingsAndSettingsView.swift)

**To add files to widget target:**
1. Select the file in Xcode Project Navigator
2. Open File Inspector (right sidebar)
3. Under **Target Membership**, check the box next to **HoursTrackerWidget**

## 🔐 Step 3: Configure App Groups

You need to update the App Group ID to match your team/bundle identifier.

### Update App Group ID

1. **Open `WidgetDataManager.swift`** and find this line (around line 29):
   ```swift
   private let appGroupID = "group.com.yourname.HoursTracker"
   ```
   
2. **Replace with your App Group ID**:
   ```swift
   private let appGroupID = "group.YOUR-TEAM-ID.HoursTracker"
   ```
   Example: `group.com.johndoe.HoursTracker`

3. **Update entitlements files** with the same App Group ID:
   - Open `HoursTracker/HoursTracker.entitlements`
   - Open `HoursTrackerWidget/HoursTrackerWidget.entitlements`
   - Replace `group.com.yourname.HoursTracker` with your App Group ID

### Enable App Groups in Xcode

#### For Main App Target:
1. Select your project in Project Navigator
2. Select the **HoursTracker** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Search for and add **App Groups**
6. Click **+** under App Groups
7. Enter your App Group ID: `group.YOUR-TEAM-ID.HoursTracker`
8. Check the box next to it

#### For Widget Target:
1. Select the **HoursTrackerWidget** target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Search for and add **App Groups**
5. Click **+** under App Groups
6. Enter the **same** App Group ID: `group.YOUR-TEAM-ID.HoursTracker`
7. Check the box next to it

**Important**: Both targets MUST use the exact same App Group ID!

## 🎨 Step 4: Build and Run

1. **Select the main app scheme** (HoursTracker)
2. **Build and run** on a device or simulator (Cmd+R)
3. The app will update widget data automatically
4. Go to your home screen and add the widget:
   - Long press on home screen
   - Tap the **+** button
   - Search for "Hours Tracker"
   - Choose widget size (Small or Medium)

## 🔒 Step 5: Add Lock Screen Widget (iOS 16+)

1. Lock your device
2. **Long press on lock screen**
3. Tap **Customize**
4. Tap on widget areas (below time or above date)
5. Search for **Hours Tracker**
6. Choose from:
   - **Circular** - Shows hours this cheque with gauge
   - **Rectangular** - Shows all three metrics
   - **Inline** - Shows today's hours in text

## 🧪 Testing

### Test Widget Updates:
1. Open the app
2. Add or edit a work entry
3. Close the app (swipe up)
4. Wait a few seconds
5. Check that widget updates with new data

### Test Widget Tap:
1. Tap on any widget
2. Should open the main app

## 🐛 Troubleshooting

### Widget Shows "No Data" or Blank
- Check that App Group IDs match in both entitlements files
- Check that App Group is enabled for both targets
- Verify App Group ID in `WidgetDataManager.swift` matches
- Try deleting and re-adding the widget

### Widget Not Appearing in Widget Gallery
- Make sure widget target is building successfully
- Check that widget is added to the bundle in `HoursTrackerWidgetBundle.swift`
- Try cleaning build folder (Cmd+Shift+K) and rebuilding

### Data Not Syncing to Widget
- Open Xcode console and check for debug logs
- Verify `WidgetDataManager.shared.updateWidgetData()` is being called
- Check UserDefaults with App Group suite name

### Build Errors
- Ensure all shared files are added to widget target
- Check that `WorkEntry.swift` and `PaySettings.swift` are in widget target membership
- Verify import statements are correct

## 📱 Widget Variants

Your app now includes **6 widget types**:

### Home Screen Widgets:
1. **Small Widget** - Circular progress with hours this cheque + stats
2. **Medium Widget** - Full stats dashboard with streak

### Lock Screen Widgets (iOS 16+):
3. **Circular** - Gauge showing hours this cheque
4. **Rectangular** - Three metrics side by side
5. **Inline** - Today's hours with streak

## 🎉 You're Done!

Once configured, your widgets will:
- ✅ Update automatically every 15 minutes
- ✅ Update when you add/edit entries
- ✅ Update when app enters background
- ✅ Show hours this cheque, today, and this month
- ✅ Display current work streak 🔥
- ✅ Match your app's dark theme

Enjoy your new widgets! 🚀
