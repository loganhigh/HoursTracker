import SwiftUI

// MARK: - History
//
// Every month with work in it, newest first, with its total. Opening a
// month asks the phone for that month's shifts; months already opened are
// cached so they still show with the phone out of reach.

struct WatchMonthsView: View {
    @EnvironmentObject private var session: WatchSession

    var body: some View {
        List(session.snapshot.months) { month in
            NavigationLink {
                WatchMonthView(month: month)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(month.id.formatted(.dateTime.month(.wide).year()))
                            .font(.footnote.weight(.semibold))
                        Text(month.shiftCount == 1 ? "1 shift" : "\(month.shiftCount) shifts")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(WatchStyle.hours(month.hours))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle("Months")
    }
}

struct WatchMonthView: View {
    @EnvironmentObject private var session: WatchSession
    let month: WatchMonth
    @State private var unreachable = false

    private var shifts: [WatchRecentShift]? { session.monthShifts[month.id] }

    var body: some View {
        List {
            Section {
                VStack(spacing: 1) {
                    Text(WatchStyle.hours(month.hours))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(month.shiftCount == 1 ? "1 shift" : "\(month.shiftCount) shifts")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            if let shifts {
                ForEach(shifts) { WatchShiftRow(shift: $0) }
            } else if unreachable || session.failedMonths.contains(month.id) {
                Text("Bring your iPhone near to load this month.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(month.id.formatted(.dateTime.month(.abbreviated).year()))
        .onAppear { unreachable = !session.loadMonth(month.id) }
    }
}

/// One logged shift: day, times and paid hours.
struct WatchShiftRow: View {
    let shift: WatchRecentShift

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(shift.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.footnote.weight(.semibold))
                Text("\(shift.start.formatted(date: .omitted, time: .shortened)) – \(shift.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(WatchStyle.hours(shift.hours))
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
        }
    }
}
