import SwiftUI

struct EntryRowView: View {
    let entry: WorkEntry
    let breakdown: Any
    let currencyCode: String
    let showPay: Bool

    /// When set, shows **PayDay** / **Cutoff** under the hours when the entry falls on those cheque dates.
    var paySettings: PaySettings? = nil
    /// Inside a grouped card (Home's Recent Shifts): no card of its own, a
    /// leading weekday circle, hairlines supplied by the parent. History
    /// still uses the stand-alone card.
    var grouped: Bool = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if grouped {
            row
                .padding(.vertical, AppSpacing.sm)
                .padding(.horizontal, AppSpacing.md)
                .contentShape(Rectangle())
        } else {
            row
                .padding(.vertical, AppSpacing.sm + 2)
                .padding(.horizontal, AppSpacing.md)
                .appCard(radius: AppRadius.md)
        }
    }

    /// Mon/Tue/… in a small tinted circle; off days and holidays take their
    /// status colour so the list scans by colour before you read it.
    private var dayCircle: some View {
        let tint: Color = isHoliday ? AppColors.positive : (entry.isOffDay ? AppColors.negative : AppColors.accent)
        return Text(Self.weekdayFormatter.string(from: entry.date))
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(Circle().fill(tint.opacity(0.14)))
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private var row: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            // At AX sizes the circle's 3 letters no longer fit and the date
            // line names the day anyway, so it steps aside for the text.
            if grouped && !typeSize.isAccessibilitySize { dayCircle }

            // LEFT: Date + time range
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(fullDate(entry.date))
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)

                    if let weather = entry.weather {
                        HStack(spacing: 3) {
                            Image(systemName: weather.symbolName)
                                .font(.caption.weight(.semibold))
                            Text(weather.temperatureText)
                                .font(AppTypography.caption.monospacedDigit())
                        }
                        .foregroundStyle(AppColors.subtext)
                    }
                }

                // Off days have nothing to say; a stat-paid holiday shows its pay.
                if !entry.isOffDay || entry.statPayHours > 0 {
                    Text(timeRangeText)
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                }
            }
            // One line each normally; at AX sizes the time range may wrap
            // rather than lose its end time.
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(0.85)

            Spacer(minLength: AppSpacing.xs)

            // RIGHT: Pay (if enabled) + Hours + period markers + Chevron
            HStack(spacing: AppSpacing.xs) {
                VStack(alignment: .trailing, spacing: 4) {
                    if showPay, !entry.isOffDay {
                        Text(currency(payValue))
                            .font(AppTypography.rowValue)
                            .foregroundStyle(AppColors.accent)
                    }

                    Text(statusLabel)
                        .font(showPay ? AppTypography.caption.monospacedDigit() : AppTypography.rowValue)
                        .foregroundStyle(statusColor)

                    ForEach(periodDayMarkers, id: \.self) { marker in
                        AppChip(text: marker, tint: markerColor(for: marker))
                    }
                }
                .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.faint)
            }
        }
    }

    // MARK: - Pay period markers

    private var periodDayMarkers: [String] {
        guard let paySettings else { return [] }
        return PayCycleEngine.periodDayMarkerLabels(for: entry.date, settings: paySettings)
    }

    private func markerColor(for marker: String) -> Color {
        switch marker {
        case "PayDay":
            return AppTheme.Colors.accent
        case "Cutoff":
            return AppTheme.Colors.danger
        default:
            return AppTheme.Colors.subtext
        }
    }

    // MARK: - Pay extraction (works even if breakdown type changes)
    private var payValue: Double {
        if let v: Double = reflect(breakdown, keys: ["pay"]) { return v }
        if let v: CGFloat = reflect(breakdown, keys: ["pay"]) { return Double(v) }
        if let v: Int = reflect(breakdown, keys: ["pay"]) { return Double(v) }
        return 0
    }

    /// A holiday reads "Holiday" in green (it's a day you're meant to be
    /// off, not a missed one); any other off day stays a red "Off".
    private var isHoliday: Bool {
        entry.isOffDay && entry.offDayReason == EntryEditorView.holidayReason
    }

    private var statusLabel: String {
        if isHoliday { return "Holiday" }
        return entry.isOffDay ? "Off" : AppTheme.Format.hours(entry.paidHours)
    }

    private var statusColor: Color {
        if isHoliday { return AppTheme.Colors.success }
        if entry.isOffDay { return AppTheme.Colors.danger }
        return showPay ? AppTheme.Colors.subtext : AppTheme.Colors.text
    }

    // MARK: - Time range extraction (tries common property names)
    private var timeRangeText: String {
        if isHoliday {
            return entry.statPayHours > 0 ? "Holiday · \(HolidayPayRule.hoursText(entry.statPayHours)) stat pay" : "Holiday"
        }
        if entry.isOffDay {
            let reason = entry.offDayReason.isEmpty ? "Off" : entry.offDayReason
            return "Off – \(reason)"
        }
        // Try to pull start/end Dates from entry with common names
        let start: Date? =
            reflect(entry, keys: ["start", "startTime", "startDate", "clockIn", "inTime", "timeIn"])
        let end: Date? =
            reflect(entry, keys: ["end", "endTime", "endDate", "clockOut", "outTime", "timeOut"])

        if let s = start, let e = end {
            return "\(time(s)) → \(time(e))"
        }

        // Fallback: if your model stores strings like "7:00 AM"
        let startStr: String? =
            reflect(entry, keys: ["startText", "startTimeText", "clockInText", "timeInText"])
        let endStr: String? =
            reflect(entry, keys: ["endText", "endTimeText", "clockOutText", "timeOutText"])

        if let s = startStr, let e = endStr, !s.isEmpty, !e.isEmpty {
            return "\(s) → \(e)"
        }

        // Last fallback
        return "—"
    }

    // MARK: - Formatting
    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    /// Weekday-first date: "Mon, Aug 4". The year appears only when the
    /// entry's year differs from the current year.
    private func fullDate(_ date: Date) -> String {
        let f = DateFormatter()
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: date) == cal.component(.year, from: Date())
        f.dateFormat = sameYear ? "EEE, MMM d" : "EEE, MMM d, yyyy"
        return f.string(from: date)
    }

    private func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    // MARK: - Reflection helper
    private func reflect<T>(_ value: Any, keys: [String]) -> T? {
        let m = Mirror(reflecting: value)
        for child in m.children {
            guard let label = child.label else { continue }
            if keys.contains(label), let casted = child.value as? T {
                return casted
            }
        }
        // also check one level deep (some models nest fields)
        for child in m.children {
            let inner = Mirror(reflecting: child.value)
            for innerChild in inner.children {
                guard let label = innerChild.label else { continue }
                if keys.contains(label), let casted = innerChild.value as? T {
                    return casted
                }
            }
        }
        return nil
    }
}
