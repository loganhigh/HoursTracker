import SwiftUI

// MARK: - Log a shift
//
// Fastest path first: repeat your last shift or a saved template for today
// in two taps (pick, then Save on the summary). Anything else is a short
// form whose every row is pre-filled from your last shift, so most edits
// are a single Digital Crown turn.

struct WatchAddShiftView: View {
    @EnvironmentObject private var session: WatchSession
    @Binding var isPresented: Bool

    private var snapshot: WatchSnapshot { session.snapshot }

    /// Your last shift's times, break and place, placed on today.
    private var lastShiftDraft: WatchShiftDraft? {
        guard let last = snapshot.recentShifts.first else { return nil }
        return WatchShiftDraft(
            day: Calendar.current.startOfDay(for: Date()),
            startMinutes: WatchStyle.minutes(of: last.start),
            endMinutes: WatchStyle.minutes(of: last.end),
            breakMinutes: last.breakMinutes,
            locationName: last.locationName
        )
    }

    private var customDraft: WatchShiftDraft {
        lastShiftDraft ?? WatchShiftDraft(
            day: Calendar.current.startOfDay(for: Date()),
            startMinutes: 7 * 60, endMinutes: 17 * 60, breakMinutes: 0, locationName: ""
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if lastShiftDraft != nil || !snapshot.templates.isEmpty {
                    Section("Quick") {
                        if let last = lastShiftDraft {
                            NavigationLink {
                                WatchShiftForm(draft: last, isPresented: $isPresented)
                            } label: {
                                quickRow(title: "Same as last", draft: last, icon: "arrow.counterclockwise")
                            }
                        }
                        ForEach(snapshot.templates.prefix(6)) { template in
                            let draft = WatchShiftDraft(
                                day: Calendar.current.startOfDay(for: Date()),
                                startMinutes: template.startMinutes, endMinutes: template.endMinutes,
                                breakMinutes: template.breakMinutes, locationName: template.locationName,
                                templateID: template.id
                            )
                            NavigationLink {
                                WatchShiftForm(draft: draft, isPresented: $isPresented)
                            } label: {
                                quickRow(title: template.name, draft: draft, icon: "square.stack.fill")
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        WatchShiftForm(draft: customDraft, isPresented: $isPresented)
                    } label: {
                        Label("Custom shift", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("Log a shift")
        }
    }

    private func quickRow(title: String, draft: WatchShiftDraft, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(WatchStyle.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text("\(WatchStyle.time(draft.startMinutes)) – \(WatchStyle.time(draft.endMinutes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Summary / form

struct WatchShiftForm: View {
    @EnvironmentObject private var session: WatchSession
    @State var draft: WatchShiftDraft
    @Binding var isPresented: Bool

    private static let breakChoices = [0, 15, 30, 45, 60, 90]

    var body: some View {
        List {
            Section {
                VStack(spacing: 2) {
                    Text(WatchStyle.hours(draft.paidHours))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if draft.endMinutes <= draft.startMinutes {
                        Text("Ends the next day")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                NavigationLink {
                    dayPicker
                } label: {
                    row("Day", dayText(draft.day))
                }
                NavigationLink {
                    WatchTimePicker(title: "Start", minutes: $draft.startMinutes, day: draft.day)
                } label: {
                    row("Start", WatchStyle.time(draft.startMinutes))
                }
                NavigationLink {
                    WatchTimePicker(title: "End", minutes: $draft.endMinutes, day: draft.day)
                } label: {
                    row("End", WatchStyle.time(draft.endMinutes))
                }
                Picker("Break", selection: $draft.breakMinutes) {
                    ForEach(Self.breakChoices + (Self.breakChoices.contains(draft.breakMinutes) ? [] : [draft.breakMinutes]),
                            id: \.self) { minutes in
                        Text(minutes == 0 ? "None" : "\(minutes) min").tag(minutes)
                    }
                }
                if !session.snapshot.places.isEmpty || !draft.locationName.isEmpty {
                    Picker("Place", selection: $draft.locationName) {
                        Text("None").tag("")
                        ForEach(placeChoices, id: \.self) { Text($0).tag($0) }
                    }
                }
            }

            Section {
                Button {
                    session.send(.addShift(draft))
                    isPresented = false
                } label: {
                    Label("Save shift", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchStyle.clockIn)
                .disabled(!isValid)
            } footer: {
                if !isValid {
                    Text(draft.paidHours > 48 ? "That's over 48 hours." : "Check the start, end and break.")
                }
            }
        }
        .navigationTitle(dayText(draft.day))
    }

    private var isValid: Bool { draft.paidHours > 0 && draft.paidHours <= 48 }

    private var placeChoices: [String] {
        var names = session.snapshot.places
        if !draft.locationName.isEmpty,
           !names.contains(where: { $0.caseInsensitiveCompare(draft.locationName) == .orderedSame }) {
            names.insert(draft.locationName, at: 0)
        }
        return names
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Today and the 13 days before it — the phone won't log future shifts.
    private var dayPicker: some View {
        List {
            ForEach(0..<14, id: \.self) { offset in
                let day = Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                Button {
                    draft.day = day
                } label: {
                    HStack {
                        Text(dayText(day))
                        Spacer()
                        if Calendar.current.isDate(day, inSameDayAs: draft.day) {
                            Image(systemName: "checkmark").foregroundStyle(WatchStyle.accent)
                        }
                    }
                }
            }
        }
        .navigationTitle("Day")
    }

    private func dayText(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

// MARK: - Time picker

/// Hour and minute wheels, driven by the Digital Crown.
struct WatchTimePicker: View {
    let title: String
    @Binding var minutes: Int
    let day: Date

    private var date: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
            },
            set: { minutes = WatchStyle.minutes(of: $0) }
        )
    }

    var body: some View {
        DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .navigationTitle(title)
    }
}
