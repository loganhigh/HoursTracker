import SwiftUI

// MARK: - Home
//
// One screen that answers "am I on the clock?": a running timer with Break
// and Clock Out while a shift is live, a big Clock In button when it isn't,
// today's and this week's hours, and the way into logging a past shift.

struct WatchHomeView: View {
    @EnvironmentObject private var session: WatchSession
    @State private var showingAddShift = false
    @State private var confirmingClockOut = false

    private var snapshot: WatchSnapshot { session.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if let banner = session.banner {
                        Text(banner)
                            .font(.footnote.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WatchStyle.accent)
                            .transition(.opacity)
                    }

                    if !snapshot.signedIn && snapshot.generatedAt == .distantPast {
                        setupCard
                    } else if let live = snapshot.liveShift {
                        liveCard(live)
                    } else {
                        clockInButton
                    }

                    totals

                    Button {
                        showingAddShift = true
                    } label: {
                        Label("Log a shift", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!snapshot.signedIn)

                    if !snapshot.recentShifts.isEmpty {
                        recent
                    }
                }
                .animation(.easeOut(duration: 0.2), value: session.banner)
            }
            .navigationTitle("Hour Tracker")
            .sheet(isPresented: $showingAddShift) {
                WatchAddShiftView(isPresented: $showingAddShift)
            }
            .confirmationDialog("Clock out and log this shift?", isPresented: $confirmingClockOut) {
                Button("Clock Out", role: .destructive) { session.send(.clockOut(at: Date())) }
                Button("Keep Working", role: .cancel) {}
            }
        }
    }

    // MARK: Pieces

    private var setupCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.title2)
            Text("Open Hour Tracker on your iPhone and sign in to start.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var clockInButton: some View {
        Button {
            session.send(.clockIn(at: Date()))
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.title2)
                Text("Clock In")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .tint(WatchStyle.clockIn)
        .disabled(!snapshot.signedIn)
    }

    private func liveCard(_ live: WatchLiveShift) -> some View {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 2) {
                    Text(Duration.seconds(live.workedSeconds(at: context.date))
                        .formatted(.time(pattern: .hourMinuteSecond)))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(live.isOnBreak ? WatchStyle.breakTint : .primary)
                    Text(live.isOnBreak
                         ? "On break"
                         : "Since \(live.startDate.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    session.send(live.isOnBreak ? .endBreak(at: Date()) : .startBreak(at: Date()))
                } label: {
                    Image(systemName: live.isOnBreak ? "play.fill" : "cup.and.saucer.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchStyle.breakTint)
                .accessibilityLabel(live.isOnBreak ? "End break" : "Start break")

                Button {
                    confirmingClockOut = true
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchStyle.clockOut)
                .accessibilityLabel("Clock out")
            }
        }
    }

    private var totals: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let live = snapshot.liveShift.map { $0.workedSeconds(at: context.date) / 3600 } ?? 0
            HStack {
                stat("Today", WatchStyle.hours(snapshot.todayHours + live))
                Divider()
                stat("Week", WatchStyle.hours(snapshot.weekHours + live))
            }
            .padding(.vertical, 6)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ForEach(snapshot.recentShifts.prefix(3)) { shift in
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
