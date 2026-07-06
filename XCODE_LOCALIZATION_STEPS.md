# Xcode Localization Setup - Step by Step

## IMPORTANT: Manual Xcode Steps Required

The localization files have been created, but you need to add them to your Xcode project manually.

## Steps to Complete Setup:

### 1. Add LocalizationManager.swift to Xcode
1. In Xcode, right-click on the `HoursTracker` folder
2. Select "Add Files to HoursTracker..."
3. Navigate to and select `LocalizationManager.swift`
4. Make sure "Copy items if needed" is unchecked (already in project)
5. Make sure "Add to targets" includes **HoursTracker**
6. Click "Add"

### 2. Add English Localizable.strings
1. In Xcode, right-click on the `HoursTracker` folder
2. Select "Add Files to HoursTracker..."
3. Navigate to and select `Localizable.strings` (the one in the main HoursTracker folder)
4. Make sure "Copy items if needed" is unchecked
5. Make sure "Add to targets" includes **HoursTracker**
6. Click "Add"

### 3. Add Spanish Localization Folder
1. In Xcode, right-click on the `HoursTracker` folder
2. Select "Add Files to HoursTracker..."
3. Navigate to and select the `es.lproj` folder
4. Make sure "Create folder references" is selected (NOT "Create groups")
5. Make sure "Add to targets" includes **HoursTracker**
6. Click "Add"

### 4. Add French Localization Folder
1. Repeat step 3 but select the `fr.lproj` folder instead

### 5. Configure Project Localization
1. Click on your project in the Project Navigator (top item)
2. Select the project (not the target) in the main area
3. Go to the "Info" tab
4. In the "Localizations" section, you should see "English"
5. Click the "+" button to add languages
6. Add "Spanish (es)" and "French (fr)"

### 6. Build and Test
1. Build the project (Cmd+B)
2. Fix any build errors if they occur
3. Run the app
4. Go to Settings > Language
5. Change to Spanish or French
6. Close and reopen the app
7. You should see some text (like the goal card) in the selected language!

## Verification Checklist

After completing the steps above, verify:

- [ ] `LocalizationManager.swift` appears in Xcode project navigator
- [ ] `Localizable.strings` appears in Xcode project navigator
- [ ] `es.lproj` folder (with folder icon, not group) appears in project
- [ ] `fr.lproj` folder (with folder icon, not group) appears in project
- [ ] Project Info shows "English", "Spanish", and "French" in Localizations
- [ ] App builds without errors
- [ ] Language picker in Settings works
- [ ] Goal card text changes when language is changed

## Troubleshooting

### "Cannot find 'L' in scope" error:
- Make sure `LocalizationManager.swift` is added to the HoursTracker target
- Clean build folder (Cmd+Shift+K) and rebuild

### "Cannot find LocalizationManager"
- Check that the file is part of the HoursTracker target
- Check the file's target membership in the File Inspector

### Language doesn't change:
- Make sure you're closing and reopening the app after changing language
- Check that the `.lproj` folders are folder references (blue folder icon)
- Verify the `Localizable.strings` files are inside the `.lproj` folders

### Text still shows in English:
- That's expected! Only the goal card has been updated so far
- You need to replace hardcoded strings with `L.*` throughout the app
- See `LOCALIZATION_SETUP.md` for the full list of files to update

## Next Steps

Once the files are added to Xcode and the app builds successfully:

1. Test language switching with the goal card
2. Gradually replace hardcoded strings in other views with `L.*` 
3. Add more localized strings to the `Localizable.strings` files as needed
4. Add remaining languages (German, Portuguese, Chinese, etc.)

## Quick Reference

Common localized strings you can use now:
```swift
L.cancel
L.done
L.save
L.edit
L.delete
L.settings
L.hours
L.days
L.biWeeklyHourGoal
L.goalMet
L.shortOfGoal
L.language
L.notifications
```

Add more as you update the views!
