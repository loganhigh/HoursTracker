# Update Summary: Theme + Freeze Fix

## Part 1 — New UI Theme (Global)

### Design System
- **`AppDesignSystem.swift`**: Centralized spacing, radius, shadows, typography constants.
- **`SemanticColors`**: Dark and light color sets (background, card, text, accent, etc.).
- **`ThemeProvider`**: Holds current semantic colors; updated when system theme changes.
- **`AppTheme`**: Now resolves colors from `ThemeProvider` (adaptive light/dark).

### Reusable Components
- **`AppCard`**: Base card with rounded corners, thin border, subtle shadow.
- **`SectionCard`**: Uses `AppCard`; optional title, subtitle, trailing view.
- **`PrimaryButton`**: Filled accent button.
- **`SecondaryButton`**: Outline accent button.
- **`StatPill`**: Value + optional label/icon in a capsule.
- **`BadgeChip`**: Selectable chip for filters.
- **`SectionHeader`**: Title + optional subtitle.
- **`EmptyStateView`**: Icon, title, message, action button.

### Light Mode Support
- `.adaptiveTheme()` modifier at app root injects semantic colors from system `colorScheme`.
- Removed all `.preferredColorScheme(.dark)` so system theme (light or dark) is respected.
- All screens now adapt to light or dark mode.

---

## Part 2 — Critical Freeze on Launch (Fix)

### Likely Root Causes Addressed
1. **Duplicate `HoursStore`**: `RootView` was creating its own `@StateObject store` instead of using the app-level store from the environment. This caused double initialization and potential race conditions.
2. **Main-thread blocking**: `save()` was doing JSON encoding on the main thread; moved to a background queue.
3. **No startup coordination**: Main UI could render before data was loaded, causing heavy work during first paint.
4. **Synchronous work in `onAppear`**: `WeeklyMilestoneNotifier` and cloud sync ran immediately; now deferred by 0.3s after first frame.

### Changes Made

#### Logging
- **`AppLogger`**: OSLog categories `app.lifecycle`, `db`, `network`, `ui`.
- Logs around app start, data load, and sync.

#### Signposts
- **`os_signpost`** around the startup phase for Instruments profiling.
- Use "Startup" as the signpost name to measure load duration.

#### Startup Flow
- **`StartupCoordinator`**: Manages loading state (loading / ready / error).
- **`SplashView`**: Shown while data loads.
- **`StartupErrorView`**: Shown on timeout or error; "Retry" and "Reset cache" actions.
- **`MainAppWithStartup`**: Shows splash → main app when ready.
- **Timeout**: 10 seconds; if load does not complete, error state with retry/reset.

#### Data Loading
- **`HoursStore.ensureDataLoaded(completion:)`**: Loads data and calls completion when ready.
- **`loadAsync`**: Runs on `DispatchQueue.global(qos: .userInitiated)`; updates on main.
- **`save()`**: JSON encoding and `UserDefaults` writes moved to `DispatchQueue.global(qos: .utility)`.

#### Single Store
- **`RootView`**: Uses `@EnvironmentObject store` instead of `@StateObject store`.
- One shared store created in `HoursTrackerApp` and passed through the environment.

#### Deferred Work
- `WeeklyMilestoneNotifier.resetWeeklyStateIfNeeded()` and `checkMilestones()` run 0.3s after main content appears.
- Cloud sync also deferred to avoid blocking first paint.

---

## Files Touched

### New
- `AppDesignSystem.swift`
- `AppLogger.swift`
- `StartupCoordinator.swift`
- `SplashView.swift`
- `ThemeProvider.swift`

### Modified
- `AppTheme.swift` — Uses `ThemeProvider`; design system integration.
- `HoursStore.swift` — Async load with completion; background save; `isLoaded`; logging.
- `HoursTrackerApp.swift` — Startup coordinator; single store; `adaptiveTheme()`.
- `RootView.swift` — Uses `@EnvironmentObject store`.
- `CompatibilityUI.swift` — `AppCard`, `SecondaryButton`, `StatPill`, `BadgeChip`, `SectionHeader`; `SectionCard` uses `AppCard`.
- `SettingsView`, `AchievementsView`, `ReportingView`, `MonthDetailView`, `InsightsView`, `ProfileView`, `EntryEditorView`, `ChatView` — Removed forced dark mode.

---

## Main Thread Checker

Enable **Main Thread Checker** in Xcode:
1. Edit Scheme → Run → Diagnostics.
2. Enable **Main Thread Checker**.

This will flag any main-thread blocking during development.
