import SwiftUI

// MARK: - Entry editor building blocks (Phase 4)
//
// Quiet, token-pure components for EntryEditorView: preset cards, field rows,
// break chips, shift-type segments, the live summary card + timeline strip,
// and the validation line. No glows; hairline strokes; flat accent fills.

// MARK: - Preset model

/// A fillable start/end/break combination (times carry hour+minute only;
/// they are merged onto the selected day when applied).
struct EntryShiftPreset {
    let start: Date
    let end: Date
    let breakMinutes: Int

    var caption: String {
        let s = start.formatted(date: .omitted, time: .shortened)
        let e = end.formatted(date: .omitted, time: .shortened)
        return breakMinutes > 0 ? "\(s)–\(e) · \(breakMinutes)m" : "\(s)–\(e)"
    }

    /// Yesterday's worked shift, if one exists.
    static func yesterday(in entries: [WorkEntry], calendar: Calendar) -> EntryShiftPreset? {
        entries
            .first { calendar.isDateInYesterday($0.date) && !$0.isOffDay }
            .map { EntryShiftPreset(start: $0.start, end: $0.end, breakMinutes: $0.breakMinutes) }
    }

    /// The most frequent start/end/break combination across all worked
    /// shifts. Hidden (nil) unless at least 3 shifts share the combo.
    static func usual(in entries: [WorkEntry], calendar: Calendar) -> EntryShiftPreset? {
        var counts: [String: (count: Int, sample: WorkEntry)] = [:]
        for entry in entries where !entry.isOffDay {
            let s = calendar.dateComponents([.hour, .minute], from: entry.start)
            let e = calendar.dateComponents([.hour, .minute], from: entry.end)
            let key = "\(s.hour ?? 0):\(s.minute ?? 0)-\(e.hour ?? 0):\(e.minute ?? 0)-\(entry.breakMinutes)"
            counts[key] = ((counts[key]?.count ?? 0) + 1, entry)
        }
        guard let best = counts.values.max(by: { $0.count < $1.count }), best.count >= 3 else { return nil }
        return EntryShiftPreset(start: best.sample.start, end: best.sample.end, breakMinutes: best.sample.breakMinutes)
    }
}

// MARK: - Quiet chip recipe (Home quick-action recipe: .12 fill / .25 stroke)

private struct EntryQuietChipBackground: ViewModifier {
    let isSelected: Bool
    let tint: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(
                shape
                    .fill(isSelected ? tint.opacity(0.12) : AppColors.card)
                    .overlay(shape.stroke(isSelected ? tint.opacity(0.25) : AppColors.stroke, lineWidth: 1))
            )
            .contentShape(shape)
    }
}

private extension View {
    func entryQuietChip(isSelected: Bool, tint: Color = AppColors.accent, radius: CGFloat = AppRadius.sm) -> some View {
        modifier(EntryQuietChipBackground(isSelected: isSelected, tint: tint, radius: radius))
    }
}

// MARK: - Quiet card container

struct EntryEditorCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
        )
    }
}

/// Leading-aligned quiet section label above a card.
struct EntrySectionLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .appText(.eyebrow)
            .foregroundStyle(AppColors.subtext)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, AppSpacing.xxs)
    }
}

// MARK: - Preset card

struct EntryPresetCard: View {
    let title: String
    let caption: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.text)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.85)
                Text(caption)
                    .font(.system(.caption2, design: .default, weight: .medium).monospacedDigit())
                    .foregroundStyle(AppColors.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 10)
            .entryQuietChip(isSelected: isSelected)
        }
        .buttonStyle(PremiumPressStyle())
    }
}

// MARK: - Expandable field row (date / start / end)

struct EntryFieldRow: View {
    let title: String
    let dayText: String
    let valueText: String
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(valueText)
                        .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(isExpanded ? AppColors.accent : AppColors.text)
                    if !dayText.isEmpty {
                        Text(dayText)
                            .appText(.caption)
                            .foregroundStyle(AppColors.faint)
                    }
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct EntryRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.stroke.opacity(0.6))
            .frame(height: 1)
    }
}

// MARK: - Break section (chip row + optional custom stepper)

struct EntryBreakSection: View {
    @Binding var breakMinutes: Int
    @Binding var showCustom: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let options: [Int] = [0, 15, 30, 45, 60]

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            EntrySectionLabel("Break")
            HStack(spacing: AppSpacing.xs) {
                ForEach(Self.options, id: \.self) { minutes in
                    chip(
                        label: minutes == 0 ? "None" : "\(minutes)m",
                        isSelected: !showCustom && breakMinutes == minutes
                    ) {
                        showCustom = false
                        breakMinutes = minutes
                    }
                }
                chip(label: "Custom", isSelected: showCustom) {
                    showCustom = true
                }
            }
            if showCustom {
                EntryEditorCard {
                    Stepper(value: $breakMinutes, in: 0...240, step: 5) {
                        Text("\(breakMinutes) min")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                            .foregroundStyle(AppColors.accent)
                    }
                    .tint(AppColors.accent)
                }
            }
        }
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.lightTap()
            withAnimation(AppMotion.animation(AppMotion.Spring.snappy, reduceMotion: reduceMotion)) {
                action()
            }
        } label: {
            Text(label)
                .font(.system(.footnote, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(isSelected ? AppColors.accent : AppColors.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.6) // six chips abreast — no mid-word wraps at AX sizes
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .entryQuietChip(isSelected: isSelected, radius: AppRadius.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shift type section (Work / Off day / Holiday + reason UI)

struct EntryShiftTypeSection: View {
    @Binding var kind: EntryEditorView.ShiftKind
    @Binding var offDayReason: String
    let reasons: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let all: [(EntryEditorView.ShiftKind, String, String)] = [
        (.work, "Work", "clock"),
        (.offDay, "Off day", "moon.zzz"),
        (.holiday, "Holiday", "airplane")
    ]

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            EntrySectionLabel("Shift type")
            HStack(spacing: AppSpacing.xs) {
                ForEach(all, id: \.0) { option in
                    segment(option)
                }
            }
            if kind == .offDay {
                EntryEditorCard {
                    HStack {
                        Text("Reason")
                            .appText(.subheadline)
                            .foregroundStyle(AppColors.subtext)
                        Spacer()
                        Picker("Reason", selection: $offDayReason) {
                            ForEach(reasons, id: \.self) { reason in
                                Text(reason).tag(reason)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.accent)
                    }
                }
            } else if kind == .holiday {
                Text("Logged as a single holiday day — no hours counted.")
                    .appText(.caption)
                    .foregroundStyle(AppColors.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, AppSpacing.xxs)
            }
        }
    }

    private func segment(_ option: (EntryEditorView.ShiftKind, String, String)) -> some View {
        let isSelected = kind == option.0
        return Button {
            guard !isSelected else { return }
            Haptics.lightTap()
            withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
                kind = option.0
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: option.2)
                    .font(.system(size: 12, weight: .semibold))
                Text(option.1)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6) // "Off day" / "Holiday" stay whole at AX sizes
            }
            .foregroundStyle(isSelected ? AppColors.accent : AppColors.subtext)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .entryQuietChip(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Details section (location + notes)

struct EntryDetailsSection: View {
    @Binding var locationLabel: String
    @Binding var notes: String
    /// Off days and holidays have no job site, so the location field is asked
    /// for on work shifts only. Notes stay for every kind.
    var showsLocation: Bool = true

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            EntrySectionLabel("Details")
            EntryEditorCard {
                if showsLocation {
                    TextField("Location or job (optional)", text: $locationLabel, axis: .vertical)
                        .appText(.body)
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1...3)
                        .tint(AppColors.accent)
                    EntryRowDivider()
                        .padding(.vertical, 10)
                }
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .appText(.body)
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1...4)
                    .tint(AppColors.accent)
            }
        }
    }
}

// MARK: - Delete row (edit mode)

struct EntryDeleteRow: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.lightTap()
            action()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                Text("Delete Shift")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(AppColors.negative)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .entryQuietChip(isSelected: true, tint: AppColors.negative, radius: AppRadius.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Live summary card

struct EntrySummaryCard: View {
    let totalHours: Double
    let regularHours: Double
    let overtimeHours: Double
    let doubleTimeHours: Double
    let start: Date
    let end: Date
    let breakMinutes: Int

    var body: some View {
        EntryEditorCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    AnimatedMetricText(hours: totalHours)
                        .appText(.heroNumber)
                        .foregroundStyle(AppColors.text)
                    Text("total")
                        .appText(.caption)
                        .foregroundStyle(AppColors.faint)
                    Spacer()
                }

                HStack(spacing: AppSpacing.xs) {
                    summaryChip(label: "Regular", hours: regularHours, tint: AppColors.subtext)
                    if overtimeHours > 0.005 {
                        summaryChip(label: "Overtime", hours: overtimeHours, tint: AppColors.accent)
                    }
                    if doubleTimeHours > 0.005 {
                        summaryChip(label: "Double time", hours: doubleTimeHours, tint: AppColors.accent)
                    }
                }

                EntryTimelineStrip(start: start, end: end, breakMinutes: breakMinutes)
                    .padding(.top, AppSpacing.xxs)
            }
        }
    }

    private func summaryChip(label: String, hours: Double, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
            AnimatedMetricText(hours: hours)
                .font(.system(.caption, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(tint.opacity(0.1))
                .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 1))
        )
    }
}

// MARK: - Read-only timeline strip

/// Slim horizontal day-span bar: the shift span as a flat accent fill on a
/// hairline track, with a small notch marking the (unpositioned) break at the
/// span's midpoint. Visual only — no interaction.
struct EntryTimelineStrip: View {
    let start: Date
    let end: Date
    let breakMinutes: Int

    private var fractions: (start: Double, end: Double) {
        let cal = Calendar.current
        let s = cal.dateComponents([.hour, .minute], from: start)
        let e = cal.dateComponents([.hour, .minute], from: end)
        let sf = (Double(s.hour ?? 0) + Double(s.minute ?? 0) / 60) / 24
        var ef = (Double(e.hour ?? 0) + Double(e.minute ?? 0) / 60) / 24
        if ef <= sf { ef = 1.0 } // overnight: draw to end of day
        return (sf, min(1, ef))
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let f = fractions
                let width = geo.size.width
                let spanStart = f.start * width
                let spanWidth = max(4, (f.end - f.start) * width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.card2)
                        .overlay(Capsule().stroke(AppColors.stroke, lineWidth: 1))
                    Capsule()
                        .fill(AppColors.accent.opacity(0.55))
                        .frame(width: spanWidth)
                        .offset(x: spanStart)
                    if breakMinutes > 0 {
                        let notchWidth = max(2, min(spanWidth * 0.6, Double(breakMinutes) / 60 / 24 * width))
                        Capsule()
                            .fill(AppColors.bg)
                            .frame(width: notchWidth, height: 4)
                            .offset(x: spanStart + spanWidth / 2 - notchWidth / 2)
                    }
                }
            }
            .frame(height: 8)
            HStack {
                Text("12a").appText(.caption).foregroundStyle(AppColors.faint)
                Spacer()
                Text("12p").appText(.caption).foregroundStyle(AppColors.faint)
                Spacer()
                Text("12a").appText(.caption).foregroundStyle(AppColors.faint)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Validation line

struct EntryValidationLine: View {
    let isValid: Bool
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .appText(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isValid ? AppColors.positive : AppColors.warning)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}
