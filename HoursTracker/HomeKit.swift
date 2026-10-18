import SwiftUI

// MARK: - Home building blocks (calendar-leaf system)
//
// Shared pieces of the redesigned Home: an hour value with its unit set
// apart, the centred section heading, the quiet full-width section button,
// the calendar leaf used on shift rows, and the tier-derived hero colour.

// MARK: Hours value

/// A number and its "h" unit as two pieces on one baseline, so values never
/// read as "41h" crammed together. Never wraps.
struct HoursValue: View {
    let hours: Double
    var size: CGFloat = 22
    var unitSize: CGFloat? = nil
    var gap: CGFloat = 4
    var color: Color = AppColors.text
    var unitColor: Color = AppColors.accent.opacity(0.75)
    var weight: Font.Weight = .heavy
    @ScaledMetric private var scale: CGFloat = 1

    /// "41", "7.5", "1,284" — the number part of `AppTheme.Format.hours`,
    /// with a grouping separator once it reaches four digits.
    static func numberText(_ hours: Double) -> String {
        guard hours.isFinite else { return "0" }
        let value = max(0, hours)
        if value >= 1000 {
            return value.formatted(.number.precision(.fractionLength(0)))
        }
        return AppTheme.Format.hours(value, suffix: "")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: gap) {
            Text(Self.numberText(hours))
                .font(.system(size: size * scale, weight: weight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text("h")
                .font(.system(size: (unitSize ?? size * 0.5) * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(unitColor)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppTheme.Format.hours(hours, suffix: " hours"))
    }
}

// MARK: Section heading

/// A section title centred on the full content width. A trailing control
/// (the Friends filter) is overlaid on the right so it never pushes the
/// title off-centre.
struct HomeSectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(AppColors.text)
            if let subtitle {
                Text(subtitle)
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) { trailing() }
        .accessibilityAddTraits(.isHeader)
    }
}

extension HomeSectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: Quiet section button

/// Full-width secondary button under a section ("View all shifts",
/// "See the full leaderboard", "Leave a tip").
struct QuietSectionButtonStyle: ButtonStyle {
    var fullWidth = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(fullWidth ? AppColors.accent : AppColors.text)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 12)
            .padding(.horizontal, fullWidth ? 0 : AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.card.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColors.accent.opacity(0.18), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: Card surface

extension View {
    /// The redesigned Home card: solid card fill with a faint tier-tinted
    /// hairline.
    func homeCard(radius: CGFloat = 22) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(AppColors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(AppColors.accent.opacity(0.14), lineWidth: 1)
        )
    }
}

// MARK: Calendar leaf

/// The recurring date object: a month band over a big day number.
/// `highlighted` (today) flips it to a light page with an accent band.
struct CalendarLeaf: View {
    let date: Date
    var highlighted = false
    var width: CGFloat = 44
    var height: CGFloat = 50

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Text(Self.monthFormatter.string(from: date).uppercased())
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(highlighted ? AppColors.textOnAccent : AppColors.accent.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(highlighted ? AppColors.accent : AppColors.accent.opacity(0.16))
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(highlighted ? Color.heroSurface : AppColors.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width, height: height)
        .background(highlighted ? Color.white.opacity(0.94) : AppColors.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(highlighted ? Color.clear : AppColors.stroke, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

// MARK: Hero colour

extension Color {
    /// The Today card's solid fill: the tier accent, more saturated and
    /// darkened until white text clears 4.5:1 contrast on it.
    static var heroSurface: Color {
        Color(UIColor(AppColors.accent).heroSurface())
    }
}

extension UIColor {
    func heroSurface() -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var color = UIColor(hue: h, saturation: min(1, s + 0.16), brightness: min(b, 0.88), alpha: 1)
        var brightness = min(b, 0.88)
        while color.relativeLuminance > 0.18, brightness > 0.2 {
            brightness -= 0.03
            color = UIColor(hue: h, saturation: min(1, s + 0.16), brightness: brightness, alpha: 1)
        }
        return color
    }

    /// WCAG relative luminance.
    var relativeLuminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}
