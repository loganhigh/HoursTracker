# Localization Setup Guide

## Overview
The app now supports multi-language localization. When users change the language in Settings, the app will update to display text in the selected language.

## How It Works

### 1. LocalizationManager
- Centralized manager that handles language switching
- Stores the current language preference in UserDefaults
- Updates the app's bundle to use the correct `.lproj` folder

### 2. Localization Helper (L struct)
- Provides easy access to localized strings throughout the app
- Example usage: `L.cancel`, `L.save`, `L.biWeeklyHourGoal`

### 3. Language Files
Localization strings are stored in `.lproj` folders:
- `HoursTracker/Localizable.strings` - English (base)
- `HoursTracker/es.lproj/Localizable.strings` - Spanish
- `HoursTracker/fr.lproj/Localizable.strings` - French

## Adding New Languages

To add a new language (e.g., German):

1. Create the language folder:
   ```bash
   mkdir -p HoursTracker/de.lproj
   ```

2. Create `Localizable.strings` file in that folder

3. Copy the English `Localizable.strings` and translate all values

4. In Xcode, add the `.lproj` folder to the project

## Using Localized Strings in Code

### Simple text:
```swift
Text(L.cancel)
Text(L.settings)
```

### Formatted strings:
```swift
Text(L.youAreShortOfGoal(hours: "5h"))
```

### Updating existing views:
Replace hardcoded strings like:
```swift
Text("Cancel") // Before
Text(L.cancel) // After
```

## Important Files to Update

To complete the localization, update these key views:

### High Priority:
1. `RootView.swift` - Main dashboard, goal card
2. `EntryEditorView.swift` - Add/Edit entry form
3. `SettingsView.swift` - Settings screen (partially done)
4. `SideMenu.swift` - Navigation menu

### Medium Priority:
5. `InsightsView.swift`
6. `ReportingView.swift`
7. `AchievementsView.swift`
8. `MonthDetailView.swift`

### Example Replacements:
```swift
// Old
.navigationTitle("Settings")
Button("Cancel") { ... }
Text("Save")

// New
.navigationTitle(L.settings)
Button(L.cancel) { ... }
Text(L.save)
```

## Adding New Strings

When adding new UI text:

1. Add the key to `Localizable.strings`:
   ```
   "new_feature" = "New Feature";
   ```

2. Add to `LocalizationManager.swift` L struct:
   ```swift
   static var newFeature: String { 
       LocalizationManager.shared.localizedString("new_feature") 
   }
   ```

3. Add translations to all language `.lproj` files

4. Use in views:
   ```swift
   Text(L.newFeature)
   ```

## Current Status

✅ Localization infrastructure created
✅ English, Spanish, French strings added
✅ Settings view updated to use localization
✅ Language picker connected to LocalizationManager

⏳ Remaining work:
- Update all views to use L.* instead of hardcoded strings
- Add remaining language files (German, Portuguese, Chinese, Japanese, Korean, Arabic)
- Test language switching throughout the app

## Testing

1. Run the app
2. Go to Settings > Language
3. Select a different language (Spanish or French)
4. Close and reopen the app
5. Verify text has changed to the selected language
