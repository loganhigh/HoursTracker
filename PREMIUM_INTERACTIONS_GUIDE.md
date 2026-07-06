# Premium Interactions Guide

This guide explains how to use the premium interaction system for dashboard cards and navigation.

## Overview

The premium interaction system provides:
1. **Press Feedback**: Smooth scale and opacity animations on tap
2. **Hero Transitions**: Morphing animations when navigating to detail screens
3. **Accessibility**: Respects Reduce Motion settings automatically

## Components

### 1. PremiumPressStyle
A button style that adds premium press feedback to any interactive element.

**Features:**
- Scales to 0.985 on press
- Reduces opacity to 0.96 on press
- Spring animation (response: 0.25, damping: 0.88)
- Makes entire area tappable with `contentShape(Rectangle())`
- Automatically disabled when Reduce Motion is enabled

**Usage:**
```swift
NavigationLink {
    DestinationView()
} label: {
    YourCardView()
}
.premiumPress()
```

### 2. HeroCard & HeroDestination
Wrappers that enable hero transitions using `matchedGeometryEffect`.

**Usage:**
```swift
// In the dashboard/list view:
@Namespace private var heroNamespace

HeroCard(id: "unique-id", namespace: heroNamespace) {
    YourCardView()
}

// In the destination view:
DestinationView()
    .heroDestination(id: "unique-id", in: heroNamespace)
```

### 3. PremiumNavigationLink
Combines navigation, press feedback, and hero transitions in one component.

**Usage:**
```swift
@Namespace private var heroNamespace

PremiumNavigationLink(
    heroID: "section-id",
    namespace: heroNamespace,
    destination: {
        DetailView()
            .heroDestination(id: "section-id", in: heroNamespace)
    },
    label: {
        SectionCard(title: "Title", subtitle: "Subtitle") {
            CardContent()
        }
    }
)
```

### 4. HeroSectionCard
A pre-configured SectionCard with hero transition support.

**Usage:**
```swift
@Namespace private var heroNamespace

HeroSectionCard(
    heroID: "month-detail",
    namespace: heroNamespace,
    title: "This Month",
    subtitle: nil,
    centerHeader: true
) {
    NavigationLink {
        MonthView()
            .heroDestination(id: "month-detail", in: heroNamespace)
    } label: {
        MonthSummaryRow(...)
    }
    .premiumPress()
}
```

## Implementation Examples

### Example 1: Simple Press Feedback (No Hero)
For cards that don't need hero transitions:

```swift
NavigationLink {
    SettingsView()
} label: {
    SectionCard(title: "Settings") {
        SettingsPreview()
    }
}
.premiumPress()
```

### Example 2: Full Hero Transition
For important sections that should morph into their destination:

```swift
@Namespace private var heroNamespace

// Dashboard card
PremiumNavigationLink(
    heroID: "achievements",
    namespace: heroNamespace,
    destination: {
        AchievementsView()
            .heroDestination(id: "achievements", in: heroNamespace)
    },
    label: {
        SectionCard(title: "Achievements", subtitle: "View all") {
            AchievementsPreview()
        }
    }
)
```

### Example 3: List Items with Press Feedback
For month rows or entry rows:

```swift
ForEach(months) { month in
    NavigationLink {
        MonthDetailView(month: month)
    } label: {
        MonthSummaryRow(month: month)
    }
    .premiumPress()
}
```

## Best Practices

### Do's ✅
- Use `@Namespace` at the view level where navigation originates
- Use unique, descriptive hero IDs (e.g., "this-month", "achievements")
- Apply `.premiumPress()` to all tappable cards/rows
- Use `PremiumNavigationLink` for major sections
- Use simple `.premiumPress()` for list items

### Don'ts ❌
- Don't create multiple `@Namespace` variables for the same navigation flow
- Don't use the same hero ID for multiple cards
- Don't manually check `accessibilityReduceMotion` - it's handled automatically
- Don't apply `PremiumPressStyle` twice (it's already in `PremiumNavigationLink`)

## Accessibility

All components automatically respect the Reduce Motion accessibility setting:
- When enabled: Hero transitions are disabled, simple fade is used
- Press feedback animations are still applied but subtle

No additional code needed - it's handled automatically by the components.

## Files Modified

- **PremiumInteractions.swift** (NEW): Contains all premium interaction components
- **RootView.swift**: Updated to use premium interactions for:
  - "This Month" section (with hero transition)
  - "Reports & Analytics" section (with hero transition)
  - "Achievements" section (with hero transition)
  - Previous month rows (press feedback only)
  - "Show more" links (press feedback only)

## Performance Notes

- Hero transitions use SwiftUI's native `matchedGeometryEffect` for optimal performance
- Animations respect device capabilities and accessibility settings
- No performance impact when Reduce Motion is enabled
- Works seamlessly with ScrollView and List (doesn't break scrolling)
