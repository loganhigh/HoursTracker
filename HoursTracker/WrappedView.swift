import SwiftUI

/// Full-screen, story-style presentation of one year's Wrapped stats.
/// Present with `.fullScreenCover`. Takes an already-computed
/// `WrappedYearStats` — this view (and every slide it renders) never touches
/// `HoursStore`/`WorkEntry` or recomputes a statistic; building the stats is
/// the caller's job (see `WrappedStatsEngine`).
struct WrappedView: View {
    let stats: WrappedYearStats
    /// The signed-in user's handle, shown on the final summary card. Passed
    /// in rather than read from a service inside the view so slides stay
    /// pure views over data handed to them.
    var username: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigator: WrappedNavigator
    /// Drives which way slides push. Set before the index changes so the
    /// transition for the incoming slide is already correct.
    @State private var isNavigatingForward = true

    init(stats: WrappedYearStats, username: String? = nil) {
        self.stats = stats
        self.username = username
        _navigator = State(initialValue: WrappedNavigator(slides: WrappedSlideType.availableSlides(for: stats)))
    }

    var body: some View {
        ZStack {
            // Base layer so there's never a flash of nothing between slides;
            // each slide draws its own tinted backdrop on top.
            WrappedPalette.background.ignoresSafeArea()

            WrappedStoryContainer(onNext: goNext, onPrevious: goPrevious) {
                ZStack {
                    if let slide = navigator.currentSlide {
                        self.slide(for: slide)
                            // Fresh identity per slide so each one replays its
                            // entrance, including when navigating backwards.
                            .id(navigator.index)
                            .transition(slideTransition)
                    }
                }
                .animation(transitionAnimation, value: navigator.index)
            }

            VStack {
                topBar
                Spacer()
            }
        }
        .statusBarHidden()
    }

    // MARK: - Transitions

    /// Directional push: the incoming slide slides in from the side you
    /// tapped toward while the outgoing one fades back, so forward and
    /// backward feel different. Under Reduce Motion this collapses to a
    /// plain cross-fade with no travel.
    private var slideTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let incomingEdge: Edge = isNavigatingForward ? .trailing : .leading
        let outgoingEdge: Edge = isNavigatingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: incomingEdge).combined(with: .opacity),
            removal: .move(edge: outgoingEdge).combined(with: .opacity)
        )
    }

    /// Quick and non-blocking on purpose: navigation state updates
    /// immediately on tap, so a fast tapper is never waiting on the previous
    /// slide's transition to finish before the next tap registers.
    private var transitionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 14) {
            WrappedProgressView(slideCount: navigator.slideCount, currentIndex: navigator.index)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WrappedPalette.primaryText)
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .accessibilityLabel("Close Wrapped")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Navigation
    //
    // Bounds are enforced by WrappedNavigator (unit-tested); tapping past
    // the final slide dismisses rather than doing nothing, so the user is
    // never stuck tapping a dead zone at the end of the story.

    private func goNext() {
        isNavigatingForward = true
        if navigator.goNext() {
            Haptics.lightTap()
        } else {
            dismiss()
        }
    }

    private func goPrevious() {
        isNavigatingForward = false
        if navigator.goPrevious() {
            Haptics.lightTap()
        }
    }

    // MARK: - Slide dispatch

    @ViewBuilder
    private func slide(for type: WrappedSlideType) -> some View {
        switch type {
        case .intro: WrappedIntroSlide(stats: stats)
        case .totalHours: WrappedTotalHoursSlide(stats: stats)
        case .totalShifts: WrappedTotalShiftsSlide(stats: stats)
        case .biggestMonth: WrappedBiggestMonthSlide(stats: stats)
        case .longestShift: WrappedLongestShiftSlide(stats: stats)
        case .workSchedule: WrappedWorkScheduleSlide(stats: stats)
        case .longShiftBreakdown: WrappedLongShiftBreakdownSlide(stats: stats)
        case .biggestWeek: WrappedBiggestWeekSlide(stats: stats)
        case .weekendVsWeekday: WrappedWeekendVsWeekdaySlide(stats: stats)
        case .workStreak: WrappedWorkStreakSlide(stats: stats)
        case .workerPersonality: WrappedWorkerPersonalitySlide(stats: stats)
        case .finalSummary: WrappedFinalSummarySlide(stats: stats, username: username)
        }
    }
}
