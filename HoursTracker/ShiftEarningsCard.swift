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

    var netHourlyRate: Double { hours > 0 ? takeHome / hours : 0 }
}

extension HoursStore {
    /// Earnings for shifts that were just saved (one entry, or both halves of
    /// a split-at-midnight shift). nil for off days, zero hours, and for
    /// anyone who hasn't entered their own wage — the card states dollar
    /// figures as fact, and the $35 placeholder rate isn't theirs.
    func shiftEarnings(for shifts: [WorkEntry]) -> ShiftEarnings? {
        let work = shifts.filter { !$0.isOffDay && $0.paidHours > 0 }
        guard !work.isEmpty, paySettings.hourlyRateSet, paySettings.hourlyWage > 0 else { return nil }
        let hours = work.reduce(0) { $0 + $1.paidHours }
        let gross = work.reduce(0) { $0 + payBreakdown(for: $1).pay }
        guard gross > 0 else { return nil }
        let ratio = TakeHomeEstimator.ratio(learned: learnedTakeHomeRatio())
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
            streak: gamificationProfile.currentStreak
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
                    .filter { !$0.isOffDay }
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

    /// Read live from the store: weather for a backdated shift lands a moment
    /// after the card opens, and the card (and share image) update with it.
    private var weather: WeatherSnapshot? {
        store.entries.first { earnings.entryIDs.contains($0.id) && $0.weather != nil }?.weather
    }

    var body: some View {
        ZStack {
            WrappedBackdrop()

            VStack(spacing: AppSpacing.lg) {
                Spacer(minLength: 0)
                ShiftEarningsCard(earnings: earnings, weather: weather)
                Text(footnote)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
                Spacer(minLength: 0)
                buttons
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl)
        }
        .task { renderShareImage() }
        .onChange(of: weather) { _, _ in renderShareImage() }
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
            ShiftEarningsCard(earnings: earnings, weather: weather)
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

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("SHIFT COMPLETE · \(dateText)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.7))
                Text("You worked")
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

            VStack(spacing: 0) {
                row("Gross earned", money(earnings.gross))
                divider
                row("Estimated take-home", money(earnings.takeHome), emphasized: true)
                divider
                row("After deductions", money(earnings.netHourlyRate) + "/hr")
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
        let h = earnings.hours
        let rounded = (h * 100).rounded() / 100
        let text = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.2f", rounded).replacingOccurrences(of: #"0$"#, with: "", options: .regularExpression)
        return "\(text) \(rounded == 1 ? "hour" : "hours")"
    }

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
