import SwiftUI
import UIKit

// MARK: - Month Wrapped Data

struct MonthWrappedData {
    let monthDate: Date
    let monthTitle: String
    let year: String
    let totalHours: Double
    let daysWorked: Int
    let regularHours: Double
    let overtimeHours: Double
    let averageShiftLength: Double
    let longestShiftLength: Double
    let longestShiftDate: Date?
    let topAchievement: (title: String, value: String)?
    let isEmpty: Bool

    static func build(monthDate: Date, store: HoursStore) -> MonthWrappedData {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else {
            return MonthWrappedData(
                monthDate: monthDate,
                monthTitle: "",
                year: "",
                totalHours: 0,
                daysWorked: 0,
                regularHours: 0,
                overtimeHours: 0,
                averageShiftLength: 0,
                longestShiftLength: 0,
                longestShiftDate: nil,
                topAchievement: nil,
                isEmpty: true
            )
        }

        let entries = store.entries.filter { $0.date >= start && $0.date < end && !$0.isOffDay }
        let workEntries = entries.filter { $0.paidHours > 0 }

        let totalHours = store.monthTotalHours(monthDate: monthDate)
        let regularHours = store.monthRegularHours(monthDate: monthDate)
        let overtimeHours = store.monthOvertimeHours(monthDate: monthDate)
        let daysWorked = Set(workEntries.map { cal.startOfDay(for: $0.date) }).count
        let shiftCount = workEntries.count
        let averageShiftLength = shiftCount > 0 ? totalHours / Double(shiftCount) : 0
        let longestEntry = workEntries.max(by: { $0.paidHours < $1.paidHours })
        let longestShiftLength = longestEntry?.paidHours ?? 0
        let longestShiftDate = longestEntry?.date

        let otDays = Set(workEntries.filter { store.payBreakdown(for: $0).overtimeHours > 0 }.map { cal.startOfDay(for: $0.date) }).count

        var topAchievement: (title: String, value: String)? = nil
        if otDays > 0 {
            topAchievement = ("OT Addict", "\(otDays) OT day\(otDays == 1 ? "" : "s")")
        } else if shiftCount > 0 {
            topAchievement = ("Shifts logged", "\(shiftCount) shift\(shiftCount == 1 ? "" : "s")")
        }
        if longestShiftLength > 0, topAchievement == nil {
            topAchievement = ("Longest shift", AppTheme.Format.hours(longestShiftLength))
        }

        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "MMMM"
        let yearFmt = DateFormatter()
        yearFmt.dateFormat = "yyyy"

        return MonthWrappedData(
            monthDate: monthDate,
            monthTitle: monthFmt.string(from: start),
            year: yearFmt.string(from: start),
            totalHours: totalHours,
            daysWorked: daysWorked,
            regularHours: regularHours,
            overtimeHours: overtimeHours,
            averageShiftLength: averageShiftLength,
            longestShiftLength: longestShiftLength,
            longestShiftDate: longestShiftDate,
            topAchievement: topAchievement,
            isEmpty: workEntries.isEmpty
        )
    }
}

// MARK: - Monthly Wrapped View

struct MonthlyWrappedView: View {
    let data: MonthWrappedData
    let onClose: () -> Void

    @State private var currentPage = 0
    @State private var shareItem: IdentifiableShareItem?
    @State private var includeWatermark = true

    private var slides: [WrappedSlide] {
        if data.isEmpty {
            return [.emptyState]
        }
        var s: [WrappedSlide] = [.title, .totalHours, .regularOvertime, .avgLongest]
        if data.topAchievement != nil {
            s.append(.highlight)
        }
        return s
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button("Close") {
                        onClose()
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.accent)

                    Spacer()

                    Button("Share") {
                        shareCurrentSlide()
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                TabView(selection: $currentPage) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        WrappedSlideView(data: data, slide: slide, includeWatermark: includeWatermark)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<slides.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? AppTheme.Colors.accent : AppTheme.Colors.subtext.opacity(0.5))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.value]) { shareItem = nil }
        }
        .onChange(of: slides.count) { _, newCount in
            if currentPage >= newCount {
                currentPage = max(0, newCount - 1)
            }
        }
    }

    private func shareCurrentSlide() {
        let safePage = min(currentPage, max(0, slides.count - 1))
        guard !slides.isEmpty else { return }
        let view = WrappedSlideView(data: data, slide: slides[safePage], includeWatermark: includeWatermark)
        let image = WrappedShareRenderer.render(view: view)
        if let image = image {
            shareItem = IdentifiableShareItem(value: image)
        }
    }
}

private struct IdentifiableShareItem: Identifiable {
    let id = UUID()
    let value: UIImage
}

// MARK: - Slide Types

private enum WrappedSlide {
    case title
    case totalHours
    case regularOvertime
    case avgLongest
    case highlight
    case emptyState
}

// MARK: - Slide View

private struct WrappedSlideView: View {
    let data: MonthWrappedData
    let slide: WrappedSlide
    let includeWatermark: Bool

    var body: some View {
        ZStack {
            AppTheme.Colors.bg

            VStack(spacing: 24) {
                Spacer()
                slideContent
                Spacer()
                if includeWatermark {
                    Text("Hour Tracker")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext.opacity(0.5))
                        .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var slideContent: some View {
        switch slide {
        case .title:
            VStack(spacing: 12) {
                Text("\(data.monthTitle) \(data.year)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Work Recap")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                Text("Made with Hour Tracker")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppTheme.Colors.subtext.opacity(0.6))
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)

        case .totalHours:
            VStack(spacing: 16) {
                Text("You logged")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                Text("\(AppTheme.Format.hours(data.totalHours, suffix: "")) hours")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(data.daysWorked) day\(data.daysWorked == 1 ? "" : "s") worked")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
            .multilineTextAlignment(.center)

        case .regularOvertime:
            if data.overtimeHours > 0 {
                VStack(spacing: 20) {
                    Text("Regular: \(AppTheme.Format.hours(data.regularHours))")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Overtime: \(AppTheme.Format.hours(data.overtimeHours))")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.accent)
                }
                .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 12) {
                    Text("No overtime this month")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("— steady grind")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
                .multilineTextAlignment(.center)
            }

        case .avgLongest:
            VStack(spacing: 20) {
                Text("Avg shift: \(AppTheme.Format.hours(data.averageShiftLength))")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Longest shift: \(AppTheme.Format.hours(data.longestShiftLength))")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if let d = data.longestShiftDate {
                    Text("Best day: \(d.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
            }
            .multilineTextAlignment(.center)

        case .highlight:
            if let a = data.topAchievement {
                VStack(spacing: 16) {
                    Text("Highlight")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                    Text(a.title)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(a.value)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.accent)
                }
                .multilineTextAlignment(.center)
            } else {
                Text("Consistency matters — keep logging.")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
            }

        case .emptyState:
            VStack(spacing: 20) {
                Text("No entries this month")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Log your first shift to get your Monthly Wrapped.")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Share Renderer

enum WrappedShareRenderer {
    static func render<Content: View>(view: Content) -> UIImage? {
        let sizedView = view.frame(width: 400, height: 700)
        let renderer = ImageRenderer(content: sizedView)
        renderer.scale = 3
        return renderer.uiImage
    }
}
