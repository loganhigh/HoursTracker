import SwiftUI

// MARK: - Shift earnings card
//
// Shown right after a work shift is saved: hours, the day's weather, where,
// the current streak, then gross, estimated take-home and the effective
// hourly rate after deductions — on a card designed to be shared.

struct ShiftEarnings: Equatable {
    let date: Date
    let hours: Double
    let gross: Double
    let takeHome: Double
    let source: TakeHomeEstimator.Source
    let currencyCode: String
    /// The saved entries, so the view can pick up weather that arrives after
    /// the card opens (backdated shifts are looked up asynchronously).
    let entryIDs: [UUID]
    /// Job site if the user set one on the shift.
    let locationName: String
    /// Worked-day streak including this shift.
    let streak: Int
    /// Gross for the whole pay period the shift falls in, this shift included.
    var chequeGross: Double = 0
    /// Last day of work on that cheque, for the "through" label.
    var chequeCutoff: Date? = nil
    /// Set when the day is a stat holiday, with the stat hours it carried.
    var holidayRule: HolidayPayRule? = nil
    var statPayHours: Double = 0

    /// Hours the day was worth at the regular rate (worked × multiplier + stat).
    var paidHourEquivalent: Double {
        holidayRule?.paidHourEquivalent(workedHours: hours, statHours: statPayHours) ?? hours
    }

    var chequeTakeHome: Double { gross > 0 ? chequeGross * (takeHome / gross) : 0 }

    var netHourlyRate: Double {
        let h = holidayRule == .statPayOnly ? statPayHours : hours
        return h > 0 ? takeHome / h : 0
    }
}

extension HoursStore {
    /// Earnings for shifts that were just saved (one entry, or both halves of
    /// a split-at-midnight shift). nil for off days, zero hours, and for
    /// anyone who hasn't entered their own wage — the card states dollar
    /// figures as fact, and the $35 placeholder rate isn't theirs.
    func shiftEarnings(for shifts: [WorkEntry]) -> ShiftEarnings? {
        // A stat holiday that wasn't worked is an off day, but it's paid.
        let work = shifts.filter { ($0.isOffDay ? $0.statPayHours : $0.paidHours) > 0 }
        guard !work.isEmpty, paySettings.hourlyRateSet, paySettings.hourlyWage > 0 else { return nil }
        let hours = work.reduce(0) { $0 + $1.paidHours }
        let gross = work.reduce(0) { $0 + payBreakdown(for: $1).pay }
        guard gross > 0 else { return nil }
        let ratio = TakeHomeEstimator.ratio(learned: learnedTakeHomeRatio())
        let cycle = PayCycleEngine.cycle(containing: work.map(\.date).min() ?? Date(), settings: paySettings)
        let chequeGross = PayCycleEngine.entries(entries, in: cycle)
            .reduce(0) { $0 + payBreakdown(for: $1).pay }
        return ShiftEarnings(
            date: work.map(\.date).min() ?? Date(),
            hours: hours,
            gross: gross,
            takeHome: gross * ratio.value,
            source: ratio.source,
            currencyCode: paySettings.currencyCode,
            entryIDs: work.map(\.id),
            locationName: work
                .map { $0.locationName.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "",
            streak: gamificationProfile.currentStreak,
            chequeGross: max(chequeGross, gross),
            chequeCutoff: cycle.cutoff,
            holidayRule: work.compactMap(\.holidayPayRule).first,
            statPayHours: work.reduce(0) { $0 + $1.statPayHours }
        )
    }

    /// Take-home ratio learned from recorded cheque totals, newest first.
    /// Gross for each period is recomputed with the same pay rules the app
    /// uses everywhere else, so the ratio isolates deductions.
    func learnedTakeHomeRatio() -> TakeHomeEstimator.Ratio? {
        guard !actualPayouts.isEmpty, let earliest = entries.map(\.date).min() else { return nil }
        var samples: [TakeHomeEstimator.Sample] = []
        var cursor = currentPayCycle()
        for _ in 0..<60 {
            cursor = PayCycleEngine.previousCycle(before: cursor, settings: paySettings)
            if let payout = actualPayout(for: cursor) {
                let gross = PayCycleEngine.entries(entries, in: cursor)
                    .reduce(0) { $0 + payBreakdown(for: $1).pay }
                samples.append(.init(gross: gross, payout: payout))
                if samples.count >= TakeHomeEstimator.maxSamples { break }
            }
            if cursor.start <= earliest { break }
        }
        return TakeHomeEstimator.learnedRatio(samples)
    }
}

/// Full-screen result shown in place of the add-shift wizard after saving.
struct ShiftEarningsView: View {
    @ObservedObject var store: HoursStore
    let earnings: ShiftEarnings
    let onDone: () -> Void

    @State private var shareImage: UIImage?
    /// Hides every dollar figure (card and share image) so the card can be
    /// shared without showing pay. Remembered between shifts.
    @AppStorage("shift_card_hide_pay") private var hidePay = false

    /// Read live from the store: weather for a backdated shift lands a moment
    /// after the card opens, and the card (and share image) update with it.
    private var weather: WeatherSnapshot? {
        store.entries.first { earnings.entryIDs.contains($0.id) && $0.weather != nil }?.weather
    }

    var body: some View {
        // The card area scrolls only when it's taller than the space left
        // (smaller phones); the share row and Done stay pinned below it. A
        // plain VStack that overflows gets centred, which pushed the top row
        // up under the status bar and Done off the bottom.
        VStack(spacing: 0) {
            // GeometryReader here only gets the space above the pinned
            // buttons, so the content's min height never runs under them.
            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.lg) {
                        // In the layout (not an overlay) so the card can never slide
                        // up under it on shorter screens.
                        HStack {
                            Spacer()
                            payToggle
                        }
                        Spacer(minLength: 0)
                        ShiftEarningsCard(earnings: earnings, weather: weather, showPay: !hidePay)
                        if !hidePay {
                            Text(footnote)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppSpacing.lg)
                                .transition(.payRedact)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.md)
                    .frame(minHeight: geo.size.height)
                    // Implicit: an @AppStorage write doesn't carry the
                    // withAnimation transaction, so the toggle alone jumped.
                    .animation(.spring(response: 0.45, dampingFraction: 0.86), value: hidePay)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            buttons
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.md)
        }
        .background { WrappedBackdrop() }
        .task { renderShareImage() }
        .onChange(of: weather) { _, _ in renderShareImage() }
        .onChange(of: hidePay) { _, _ in renderShareImage() }
    }

    private var payToggle: some View {
        Button {
            Haptics.lightTap()
            hidePay.toggle()
        } label: {
            Image(systemName: hidePay ? "eye.slash.fill" : "eye.fill")
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .padding(.top, AppSpacing.sm)
        .accessibilityLabel(hidePay ? "Show pay" : "Hide pay")
    }

    private var footnote: String {
        switch earnings.source {
        case .learned(let cheques):
            return "Take-home estimated from your last \(cheques) recorded cheques. These are predictions, so your final pay may differ."
        case .assumed:
            return "Add your actual cheque in History to improve future estimates. These are predictions, so your final pay may differ."
        }
    }

    private var buttons: some View {
        VStack(spacing: AppSpacing.md) {
            ShiftShareRow(image: shareImage)
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
    }

    /// A still of the card on its own backdrop, for sharing. Rendered once;
    /// the backdrop is frozen at its resting pose.
    @MainActor
    private func renderShareImage() {
        let content = ZStack {
            WrappedRibbonField.night
            WrappedRibbonField(time: 0)
            LinearGradient(
                colors: [WrappedRibbonField.night.opacity(0.20), WrappedRibbonField.night.opacity(0.50)],
                startPoint: .top,
                endPoint: .bottom
            )
            ShiftEarningsCard(earnings: earnings, weather: weather, showPay: !hidePay)
                .padding(28)
        }
        .frame(width: 390, height: 640)
        .clipped()

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        shareImage = renderer.uiImage
    }
}

/// The card itself — shared by the on-screen view and the share image.
struct ShiftEarningsCard: View {
    let earnings: ShiftEarnings
    let weather: WeatherSnapshot?
    var showPay: Bool = true

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("\(earnings.holidayRule == nil ? "SHIFT COMPLETE" : "STAT HOLIDAY") · \(dateText)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(earnings.holidayRule == .statPayOnly ? "You're paid for" : "You worked")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(hoursText)
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            if !stats.isEmpty {
                HStack(spacing: 10) {
                    ForEach(stats, id: \.label) { stat in
                        VStack(spacing: 5) {
                            Image(systemName: stat.symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .symbolRenderingMode(.multicolor)
                                .foregroundStyle(Color.white)
                                .frame(height: 20)
                            Text(stat.value)
                                .font(.system(size: 16, weight: .bold, design: .default))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(stat.label)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                }
            }

            if showPay {
                VStack(spacing: 0) {
                    if let rule = earnings.holidayRule, rule.isWorked {
                        row("Paid as", "\(HolidayPayRule.hoursText(earnings.paidHourEquivalent)) · \(rule.shortTitle)")
                        divider
                    }
                    row("Gross earned", money(earnings.gross))
                    divider
                    row("Estimated take-home", money(earnings.takeHome), emphasized: true)
                    divider
                    row("After deductions", money(earnings.netHourlyRate) + "/hr")
                    if earnings.chequeGross > earnings.gross + 0.005 {
                        divider
                        row(chequeLabel, money(earnings.chequeTakeHome))
                    }
                }
                .transition(.payRedact)
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
    }

    private struct Stat {
        let symbol: String
        let value: String
        let label: String
    }

    /// Weather, place and streak — each shown only when there's something
    /// real to show.
    private var stats: [Stat] {
        var out: [Stat] = []
        if let weather {
            out.append(Stat(symbol: weather.symbolName, value: weather.temperatureText, label: weather.conditionText))
        }
        let city = weather?.locality ?? ""
        if !earnings.locationName.isEmpty {
            out.append(Stat(symbol: "mappin.circle.fill", value: earnings.locationName,
                            label: city.isEmpty ? "Location" : city))
        } else if !city.isEmpty {
            out.append(Stat(symbol: "mappin.circle.fill", value: city, label: "Location"))
        }
        if let rule = earnings.holidayRule {
            out.append(Stat(symbol: "star.circle.fill", value: rule.isWorked ? "\(HolidayPayRule.multText(rule.workedMultiplier))×" : "Paid",
                            label: "Stat holiday"))
        }
        if earnings.streak > 0 {
            out.append(Stat(symbol: "flame.fill", value: "\(earnings.streak)", label: "day streak"))
        }
        return out
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(height: 1)
    }

    private func row(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
            Spacer(minLength: 12)
            // Standard design, not rounded: SF Rounded's bold "$" loses its
            // stroke at this size and reads as an "S".
            Text(value)
                .font(.system(size: emphasized ? 22 : 18, weight: .bold, design: .default))
                .foregroundStyle(Color.white)
                .monospacedDigit()
        }
        .padding(.vertical, 14)
    }

    private var hoursText: String {
        let h = earnings.holidayRule == .statPayOnly ? earnings.statPayHours : earnings.hours
        let rounded = (h * 100).rounded() / 100
        let text = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.2f", rounded).replacingOccurrences(of: #"0$"#, with: "", options: .regularExpression)
        return "\(text) \(rounded == 1 ? "hour" : "hours")"
    }

    /// Take-home for the pay period so far, this shift included.
    private var chequeLabel: String { "This cheque so far" }

    private var dateText: String {
        earnings.date.formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }

    private func money(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = earnings.currencyCode
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

// MARK: - Hide-pay animation

private struct PayRedactModifier: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: hidden ? 14 : 0)
            .opacity(hidden ? 0 : 1)
            .scaleEffect(hidden ? 0.94 : 1, anchor: .top)
    }
}

extension AnyTransition {
    /// Pay figures blur out as if censored (and sharpen back in) while the
    /// card resizes around them, rather than blinking away.
    static var payRedact: AnyTransition {
        .modifier(active: PayRedactModifier(hidden: true), identity: PayRedactModifier(hidden: false))
    }
}
