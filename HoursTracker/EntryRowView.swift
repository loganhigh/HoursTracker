import SwiftUI

struct EntryRowView: View {
    let entry: WorkEntry
    let breakdown: Any
    let currencyCode: String
    let showPay: Bool

    /// When set, shows **PayDay** / **Cutoff** under the hours when the entry falls on those cheque dates.
    var paySettings: PaySettings? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // LEFT: Date + time range
            VStack(alignment: .leading, spacing: 6) {
                Text(fullDate(entry.date))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)

                if !entry.isOffDay {
                    Text(timeRangeText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
            }

            Spacer(minLength: 10)

            // RIGHT: Pay (if enabled) + Hours + Chevron
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 6) {
                    if showPay, !entry.isOffDay {
                        Text(currency(payValue))
                            .font(AppDesignSystem.Typography.heroNumerals(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }

                    Text(entry.isOffDay ? "Off" : AppTheme.Format.hours(entry.paidHours))
                        .font(AppDesignSystem.Typography.heroNumerals(size: showPay ? 15 : 17, weight: .bold))
                        .foregroundStyle(entry.isOffDay ? AppTheme.Colors.danger : (showPay ? AppTheme.Colors.subtext : AppTheme.Colors.text))

                    ForEach(periodDayMarkers, id: \.self) { marker in
                        Text(marker)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(markerColor(for: marker))
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.subtext.opacity(0.5))
            }
        }
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

    // MARK: - Time range extraction (tries common property names)
    private var timeRangeText: String {
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

    private func fullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
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
