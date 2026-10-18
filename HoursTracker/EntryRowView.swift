import SwiftUI

struct EntryRowView: View {
    let entry: WorkEntry
    let breakdown: Any
    let currencyCode: String
    let showPay: Bool

    /// When set, shows **PayDay** / **Cutoff** under the hours when the entry falls on those cheque dates.
    var paySettings: PaySettings? = nil
    /// Home's calendar-leaf row (see `leafContent`). History keeps the
    /// original quiet card.
    var leaf: Bool = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if leaf {
            leafRow
        } else {
            content
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                        .fill(AppTheme.Colors.card2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                        .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
                )
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            // LEFT: Date + time range
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(fullDate(entry.date))
                        .font(.system(.body, design: .rounded, weight: .heavy))
                        .foregroundStyle(AppTheme.Colors.text)

                    if let weather = entry.weather {
                        HStack(spacing: 3) {
                            Image(systemName: weather.symbolName)
                                .font(.system(size: 12, weight: .semibold))
                            Text(weather.temperatureText)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(AppTheme.Colors.subtext)
                    }
                }

                // Off days have nothing to say; a stat-paid holiday shows its pay.
                if !entry.isOffDay || entry.statPayHours > 0 {
                    Text(timeRangeText)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
            }

            Spacer(minLength: 10)

            // RIGHT: Pay (if enabled) + Hours + Chevron
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 6) {
                    if showPay, !entry.isOffDay {
                        Text(currency(payValue))
                            .font(.system(.body, design: .rounded, weight: .heavy).monospacedDigit())
                            .foregroundStyle(AppTheme.Colors.accent)
                    }

                    Text(statusLabel)
                        .font(.system(showPay ? .subheadline : .body, design: .rounded, weight: .heavy).monospacedDigit())
                        .foregroundStyle(statusColor)

                    ForEach(periodDayMarkers, id: \.self) { marker in
                        Text(marker)
                            .font(.system(.caption2, design: .rounded, weight: .heavy))
                            .foregroundStyle(markerColor(for: marker))
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.subtext.opacity(0.5))
            }
        }
    }


    // MARK: - Calendar-leaf row (Home)

    private var isToday: Bool { Calendar.current.isDateInToday(entry.date) }

    /// Leaf tile · weekday + time · hours · chevron. Only today's row gets a
    /// surface (a faint accent tint); the rest sit flat on the page.
    private var leafRow: some View {
        HStack(spacing: 12) {
            CalendarLeaf(date: entry.date, highlighted: isToday)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(weekdayTitle)
                        .font(.system(.subheadline, design: .rounded, weight: isToday ? .bold : .semibold))
                        .foregroundStyle(AppTheme.Colors.text)
                        .lineLimit(1)
                    ForEach(periodDayMarkers, id: \.self) { marker in
                        Text(marker.uppercased())
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(marker == "PayDay" ? Color(red: 0.10, green: 0.07, blue: 0) : .white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(marker == "PayDay" ? AppColors.rankGold : AppTheme.Colors.danger))
                            .fixedSize()
                    }
                }
                Text(leafSubtitle)
                    .font(.system(.footnote, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if entry.isOffDay {
                Text(statusLabel)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(statusColor)
            } else {
                HoursValue(hours: entry.paidHours, size: 22, unitSize: 12, gap: 4)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.Colors.subtext.opacity(0.5))
        }
        .padding(.vertical, 9)
        .padding(.horizontal, isToday ? 12 : 0)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColors.accent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColors.accent.opacity(0.32), lineWidth: 1)
                    )
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Friday" — plus the year when it isn't this year.
    private var weekdayTitle: String {
        let f = DateFormatter()
        let sameYear = Calendar.current.component(.year, from: entry.date) == Calendar.current.component(.year, from: Date())
        f.dateFormat = sameYear ? "EEEE" : "EEEE, yyyy"
        return f.string(from: entry.date)
    }

    /// Time range, with the pay appended when pay is shown.
    private var leafSubtitle: String {
        guard showPay, !entry.isOffDay else { return timeRangeText }
        return "\(timeRangeText) · \(currency(payValue))"
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
