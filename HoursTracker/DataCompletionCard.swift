import Combine
import SwiftUI

// MARK: - Data Completion card (History tab)
//
// Surfaces MissingShiftDetector's findings: a completion score for the last
// three weeks of usual workdays, and up to three days that may be missing a
// shift. Nothing is ever logged automatically — every suggestion waits for
// the user to add a shift, mark the day off, or dismiss it.

/// Days the user dismissed from the missing-shift suggestions. Local-only and
/// account-bound: cleared on sign-out and on delete-all-data.
final class MissingShiftDismissals: ObservableObject {
    static let shared = MissingShiftDismissals()
    static let storageKey = "missing_shift_dismissed_v1"

    @Published private(set) var dayKeys: Set<String>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dayKeys = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    func dismiss(_ day: Date) {
        dayKeys.insert(MissingShiftDetector.dayKey(day))
        prune()
        defaults.set(Array(dayKeys).sorted(), forKey: Self.storageKey)
    }

    func removeAll() {
        dayKeys = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// Keys older than the detector could ever look at again are dead weight.
    private func prune() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) else { return }
        let cutoffKey = MissingShiftDetector.dayKey(cutoff)
        dayKeys = dayKeys.filter { $0 >= cutoffKey }
    }
}

struct DataCompletionCard: View {
    @ObservedObject var store: HoursStore
    @ObservedObject private var dismissals = MissingShiftDismissals.shared

    /// Owned by the host screen (see `dataCompletionPresentations`) so the
    /// add-shift cover and "See all" sheet survive this card disappearing
    /// the moment its last suggestion is resolved.
    @Binding var addShiftFor: MissingShiftDetector.Suggestion?
    @Binding var showingAll: Bool

    private static let previewLimit = 3

    private var report: MissingShiftDetector.Report? {
        MissingShiftDetector.analyze(
            entries: store.allEntriesIncludingArchive(),
            dismissedDayKeys: dismissals.dayKeys,
            weekStartWeekday: store.paySettings.weekStartWeekday
        )
    }

    var body: some View {
        if let report, !report.suggestions.isEmpty {
            card(report)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func card(_ report: MissingShiftDetector.Report) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            header(report)
            ForEach(report.suggestions.prefix(Self.previewLimit)) { suggestion in
                Divider().overlay(AppColors.stroke)
                MissingShiftRow(
                    suggestion: suggestion,
                    onAddShift: { addShiftFor = suggestion },
                    onDayOff: { MissingShiftActions.logDayOff(suggestion.day, store: store) },
                    onDismiss: { MissingShiftActions.dismiss(suggestion.day) }
                )
            }
            if report.suggestions.count > Self.previewLimit {
                Divider().overlay(AppColors.stroke)
                Button {
                    Haptics.lightTap()
                    showingAll = true
                } label: {
                    HStack {
                        Text("See all \(report.suggestions.count)")
                            .appText(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(PremiumPressStyle())
            }
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
        )
    }

    private func header(_ report: MissingShiftDetector.Report) -> some View {
        HStack(spacing: AppSpacing.sm) {
            CompletionRing(score: report.score)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Data completion")
                    .appText(.eyebrow)
                    .foregroundStyle(AppColors.subtext)
                Text("\(Int((report.score * 100).rounded(.down)))% complete")
                    .appText(.headline)
                    .foregroundStyle(AppColors.text)
                Text("Your usual workdays, last 3 weeks")
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Presentations driven by `DataCompletionCard`, attached to its host.
    func dataCompletionPresentations(
        store: HoursStore,
        addShiftFor: Binding<MissingShiftDetector.Suggestion?>,
        showingAll: Binding<Bool>
    ) -> some View {
        self
            .fullScreenCover(item: addShiftFor) { suggestion in
                AddShiftEntryView(store: store, initialDate: suggestion.day)
            }
            .sheet(isPresented: showingAll) {
                MissingShiftListSheet(store: store)
            }
    }
}

// MARK: - Actions

enum MissingShiftActions {
    /// Marks the day off through the store's normal save/sync path. If the
    /// app already auto-filled an "Off" placeholder there, that entry is
    /// confirmed in place (`update` stamps it as a user edit) instead of
    /// stacking a duplicate off day on the same date.
    static func logDayOff(_ day: Date, store: HoursStore) {
        let cal = Calendar.current
        let sameDay = store.entries.filter { cal.isDate($0.date, inSameDayAs: day) }
        if let placeholder = sameDay.first(where: { MissingShiftDetector.isAutoPlaceholder($0, calendar: cal) }) {
            withAnimation(AppMotion.Spring.smooth) { store.update(placeholder) }
        } else if sameDay.isEmpty {
            let start = cal.startOfDay(for: day)
            let entry = WorkEntry(
                date: start,
                start: start,
                end: start,
                breakMinutes: 0,
                notes: "",
                isOffDay: true,
                offDayReason: "Off"
            )
            withAnimation(AppMotion.Spring.smooth) { store.add(entry) }
        } else {
            // Something already sits on the day outside what this card can
            // edit (e.g. an archived entry) — just stop suggesting it.
            MissingShiftDismissals.shared.dismiss(day)
        }
        Haptics.success()
    }

    static func dismiss(_ day: Date) {
        Haptics.lightTap()
        withAnimation(AppMotion.Spring.smooth) {
            MissingShiftDismissals.shared.dismiss(day)
        }
    }
}

// MARK: - Row

struct MissingShiftRow: View {
    let suggestion: MissingShiftDetector.Suggestion
    let onAddShift: () -> Void
    let onDayOff: () -> Void
    let onDismiss: () -> Void

    private var title: String {
        let day = suggestion.day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return "\(day) may be missing a shift."
    }

    private var subtitle: String {
        let symbols = Calendar.current.weekdaySymbols
        let name = symbols.indices.contains(suggestion.weekday - 1) ? symbols[suggestion.weekday - 1] : ""
        return "You normally work \(name)s."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .top, spacing: AppSpacing.xs) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.warning)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: AppSpacing.xs) {
                pill("Add shift", systemImage: "plus", prominent: true, action: onAddShift)
                pill("Day off", systemImage: "moon.zzz", prominent: false, action: onDayOff)
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .padding(.vertical, 6)
                        .padding(.horizontal, AppSpacing.xs)
                }
                .buttonStyle(PremiumPressStyle())
                .accessibilityHint("Stops suggesting this day")
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    private func pill(_ title: String, systemImage: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .appText(.caption)
                .foregroundStyle(prominent ? AppColors.textOnAccent : AppColors.accent)
                .padding(.vertical, 6)
                .padding(.horizontal, AppSpacing.sm)
                .background(
                    Capsule().fill(prominent ? AppColors.accent : AppColors.accent.opacity(0.12))
                )
        }
        .buttonStyle(PremiumPressStyle())
    }
}

// MARK: - Score ring

private struct CompletionRing: View {
    let score: Double

    private var tint: Color {
        score >= 0.9 ? AppColors.positive : (score >= 0.7 ? AppColors.warning : AppColors.negative)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.stroke, lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, score)))
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(AppMotion.Spring.smooth, value: score)
            Image(systemName: "checklist")
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - See all

private struct MissingShiftListSheet: View {
    @ObservedObject var store: HoursStore
    @ObservedObject private var dismissals = MissingShiftDismissals.shared
    @Environment(\.dismiss) private var dismiss
    @State private var addShiftFor: MissingShiftDetector.Suggestion?

    private var suggestions: [MissingShiftDetector.Suggestion] {
        MissingShiftDetector.analyze(
            entries: store.allEntriesIncludingArchive(),
            dismissedDayKeys: dismissals.dayKeys,
            weekStartWeekday: store.paySettings.weekStartWeekday
        )?.suggestions ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    if suggestions.isEmpty {
                        AppEmptyState(
                            icon: "checkmark.circle",
                            title: "All caught up",
                            message: "Every usual workday in the last 3 weeks is accounted for."
                        )
                        .padding(.top, AppSpacing.xxl)
                    }
                    ForEach(suggestions) { suggestion in
                        MissingShiftRow(
                            suggestion: suggestion,
                            onAddShift: { addShiftFor = suggestion },
                            onDayOff: { MissingShiftActions.logDayOff(suggestion.day, store: store) },
                            onDismiss: { MissingShiftActions.dismiss(suggestion.day) }
                        )
                        Divider().overlay(AppColors.stroke)
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Possibly missing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(item: $addShiftFor) { suggestion in
                AddShiftEntryView(store: store, initialDate: suggestion.day)
            }
        }
    }
}
