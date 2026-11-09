import SwiftUI

// MARK: - Friend's cheque, day by day
//
// "How many hours did we work on the 13th?" — every day of the friend's
// current cheque with their hours, and yours beside it for the same day.
// Data: `publicProfiles/{uid}.chequeDailySummary` (server-published, gated
// by the friend's "Show hours to friends" setting).

struct FriendChequeDaysCard: View {
    let friend: FriendProfile
    let accent: Color
    @EnvironmentObject private var store: HoursStore

    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    /// Every day of the cheque window up to today, newest first; days with
    /// nothing logged appear with 0 hours.
    private var days: [FriendDailyEntry] {
        let iso = FriendDailyEntry.isoFormatter
        let cal = Calendar.current
        guard let start = iso.date(from: friend.chequeWindowStart),
              let cutoff = iso.date(from: friend.chequeWindowCutoff) else {
            return friend.chequeDailySummary.sorted { $0.date > $1.date }
        }
        let byDate = Dictionary(friend.chequeDailySummary.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [FriendDailyEntry] = []
        var cursor = cal.startOfDay(for: start)
        let last = min(cal.startOfDay(for: cutoff), cal.startOfDay(for: Date()))
        while cursor <= last {
            let key = iso.string(from: cursor)
            result.append(byDate[key] ?? FriendDailyEntry(date: key, hours: 0, shifts: 0))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result.reversed()
    }

    /// Your own paid hours per ISO day, for the "You" column.
    private var myHoursByDay: [String: Double] {
        let iso = FriendDailyEntry.isoFormatter
        var map: [String: Double] = [:]
        for entry in store.entries where !entry.isOffDay {
            map[iso.string(from: entry.date), default: 0] += entry.paidHours
        }
        return map
    }

    private var rangeText: String {
        let iso = FriendDailyEntry.isoFormatter
        guard let s = iso.date(from: friend.chequeWindowStart),
              let e = iso.date(from: friend.chequeWindowCutoff) else { return "Current cheque" }
        return "\(Self.rangeFormatter.string(from: s)) – \(Self.rangeFormatter.string(from: e))"
    }

    var body: some View {
        let days = days
        let mine = myHoursByDay
        let total = days.reduce(0) { $0 + $1.hours }
        // Your hours over the SAME days (their cheque window), so the gap
        // compares like with like.
        let myTotal = days.reduce(0) { $0 + (mine[$1.date] ?? 0) }

        // Title inside the card so its top edge stays flat for the owl peek.
            VStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("This cheque")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(AppColors.text)
                    Text(rangeText)
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, AppSpacing.md)

                if !days.isEmpty {
                    gapChip(myTotal: myTotal, theirTotal: total)
                        .padding(.top, AppSpacing.xs)
                }

                HStack {
                    let workedCount = days.filter { $0.hours > 0 }.count
                    Text("\(workedCount) \(workedCount == 1 ? "day" : "days") worked")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                    Spacer()
                    HoursValue(hours: total, size: 18, unitSize: 11, gap: 4, unitColor: accent.opacity(0.8))
                }
                .padding(.vertical, 10)

                columnHeader

                if days.isEmpty {
                    Text("No days in this cheque yet.")
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                        .padding(.vertical, AppSpacing.md)
                } else {
                    ForEach(days) { day in
                        Divider().overlay(AppColors.stroke)
                        dayRow(day, myHours: mine[day.date] ?? 0)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, AppSpacing.xxs)
            .homeCard()
    }

    /// "You're 6.5h ahead of tyler" / "behind" / "tied" for this cheque.
    private func gapChip(myTotal: Double, theirTotal: Double) -> some View {
        let diff = myTotal - theirTotal
        let tied = abs(diff) < 0.05
        let ahead = diff > 0
        let amount = AppTheme.Format.hours(abs(diff), suffix: "h")
        let text = tied
            ? "You're tied with \(friend.displayName)"
            : "You're \(amount) \(ahead ? "ahead of" : "behind") \(friend.displayName)"
        let tint = tied ? AppColors.subtext : (ahead ? AppColors.positive : AppColors.negative)
        let icon = tied ? "equal" : (ahead ? "arrow.up.right" : "arrow.down.right")
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            Text(text)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    private var columnHeader: some View {
        HStack(spacing: AppSpacing.sm) {
            Spacer()
            Text(friend.displayName)
                .lineLimit(1)
                .frame(width: 72, alignment: .trailing)
            Text("You")
                .frame(width: 52, alignment: .trailing)
        }
        .font(.system(.caption2, design: .rounded, weight: .bold))
        .foregroundStyle(AppColors.subtext)
        .padding(.bottom, 6)
    }

    private func dayRow(_ day: FriendDailyEntry, myHours: Double) -> some View {
        let date = day.calendarDate ?? Date()
        let isToday = Calendar.current.isDateInToday(date)
        let worked = day.hours > 0
        return HStack(spacing: AppSpacing.sm) {
            CalendarLeaf(date: date, highlighted: isToday, width: 38, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.weekdayFormatter.string(from: date))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                if day.shifts > 1 {
                    Text("\(day.shifts) shifts")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
            }
            Spacer(minLength: AppSpacing.xs)
            Group {
                if worked {
                    HoursValue(hours: day.hours, size: 18, unitSize: 11, gap: 4, unitColor: accent.opacity(0.8))
                } else {
                    Text("—").font(.system(.body, design: .rounded, weight: .bold)).foregroundStyle(AppColors.faint)
                }
            }
            .frame(width: 72, alignment: .trailing)
            Group {
                if myHours > 0 {
                    HoursValue(hours: myHours, size: 15, unitSize: 10, gap: 3,
                               color: AppColors.subtext, unitColor: AppColors.subtext.opacity(0.7), weight: .bold)
                } else {
                    Text("—").font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(AppColors.faint)
                }
            }
            .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .opacity(worked || myHours > 0 ? 1 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Self.weekdayFormatter.string(from: date)), \(date.formatted(.dateTime.month().day())): \(friend.displayName) \(worked ? AppTheme.Format.hours(day.hours, suffix: " hours") : "no hours"), you \(myHours > 0 ? AppTheme.Format.hours(myHours, suffix: " hours") : "no hours")"))
    }
}
