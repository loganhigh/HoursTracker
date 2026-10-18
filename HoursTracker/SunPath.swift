import SwiftUI

// MARK: - Sun path (Today card)
//
// Sunrise and sunset are computed on-device from the weather location, so the
// dome needs no extra network call and works from the cached snapshot.

enum SunTimes {
    /// Sunrise and sunset for the calendar day containing `date` at the given
    /// coordinates (NOAA sunrise equation, ~1 minute accuracy). Nil during
    /// polar day or night.
    static func sunriseSunset(on date: Date, latitude: Double, longitude: Double,
                              calendar: Calendar = .current) -> (sunrise: Date, sunset: Date)? {
        guard let rise = event(rising: true, date: date, latitude: latitude, longitude: longitude, calendar: calendar),
              let set = event(rising: false, date: date, latitude: latitude, longitude: longitude, calendar: calendar),
              rise < set else { return nil }
        return (rise, set)
    }

    private static func event(rising: Bool, date: Date, latitude: Double, longitude: Double,
                              calendar: Calendar) -> Date? {
        let rad = Double.pi / 180
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }
        let lngHour = longitude / 15
        let t = Double(dayOfYear) + ((rising ? 6 : 18) - lngHour) / 24
        let m = 0.9856 * t - 3.289
        var l = m + 1.916 * sin(m * rad) + 0.020 * sin(2 * m * rad) + 282.634
        l = l.truncatingRemainder(dividingBy: 360); if l < 0 { l += 360 }
        var ra = atan(0.91764 * tan(l * rad)) / rad
        ra = ra.truncatingRemainder(dividingBy: 360); if ra < 0 { ra += 360 }
        ra += (floor(l / 90) * 90) - (floor(ra / 90) * 90)
        ra /= 15
        let sinDec = 0.39782 * sin(l * rad)
        let cosDec = cos(asin(sinDec))
        let cosH = (cos(90.833 * rad) - sinDec * sin(latitude * rad)) / (cosDec * cos(latitude * rad))
        guard cosH >= -1, cosH <= 1 else { return nil }
        var h = rising ? 360 - acos(cosH) / rad : acos(cosH) / rad
        h /= 15
        let localMean = h + ra - 0.06571 * t - 6.622
        var ut = (localMean - lngHour).truncatingRemainder(dividingBy: 24); if ut < 0 { ut += 24 }

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let ymd = calendar.dateComponents([.year, .month, .day], from: date)
        guard let utcMidnight = utc.date(from: ymd) else { return nil }
        var result = utcMidnight.addingTimeInterval(ut * 3600)
        let dayStart = calendar.startOfDay(for: date)
        // UT wraps at midnight UTC, so pull the event onto the local day.
        while result < dayStart { result.addTimeInterval(86_400) }
        while result >= dayStart.addingTimeInterval(86_400) { result.addTimeInterval(-86_400) }
        return result
    }
}

/// A true semicircle from sunrise to sunset with the sun at the current
/// time. Without a location it spans 6 AM → 9 PM and captions the time.
struct SunDome: View {
    let now: Date
    let times: (sunrise: Date, sunset: Date)?
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    private var span: (start: Date, end: Date) {
        if let times { return (times.sunrise, times.sunset) }
        let day = Calendar.current.startOfDay(for: now)
        return (day.addingTimeInterval(6 * 3600), day.addingTimeInterval(21 * 3600))
    }

    /// 0…1 through the daylight span; nil once the sun is down.
    private var progress: Double? {
        let (start, end) = span
        guard now >= start, now <= end else { return nil }
        return now.timeIntervalSince(start) / end.timeIntervalSince(start)
    }

    var body: some View {
        VStack(spacing: 4) {
            dome
                .frame(width: 118, height: 66)
            if let times {
                HStack {
                    Text("↑ \(Self.timeFormatter.string(from: times.sunrise))")
                    Spacer(minLength: 0)
                    Text("↓ \(Self.timeFormatter.string(from: times.sunset))")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.horizontal, 4)
            }
            caption
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
        }
        .frame(width: 118)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var dome: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let base = h - 7
            // Inset so the sun and its halo never clip at the ends or top.
            let r = min(w / 2 - 9, base - 9)
            let center = CGPoint(x: w / 2, y: base)
            let gold = Color(red: 0.95, green: 0.76, blue: 0.31)

            var sky = Path()
            sky.addArc(center: center, radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            sky.closeSubpath()
            context.fill(sky, with: .color(Color.black.opacity(0.22)))

            var track = Path()
            track.addArc(center: center, radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            context.stroke(track, with: .color(.white.opacity(0.25)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))

            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: base + 0.5))
            horizon.addLine(to: CGPoint(x: w, y: base + 0.5))
            context.stroke(horizon, with: .color(.white.opacity(0.32)), lineWidth: 1)

            if let p = progress {
                let angle = 180 + 180 * p
                var travelled = Path()
                travelled.addArc(center: center, radius: r, startAngle: .degrees(180), endAngle: .degrees(angle), clockwise: false)
                context.stroke(travelled, with: .color(gold), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                let rads = angle * .pi / 180
                let sun = CGPoint(x: center.x + r * cos(rads), y: center.y + r * sin(rads))
                context.fill(Path(ellipseIn: CGRect(x: sun.x - 14, y: sun.y - 14, width: 28, height: 28)),
                             with: .radialGradient(Gradient(colors: [gold.opacity(0.5), gold.opacity(0)]),
                                                   center: sun, startRadius: 0, endRadius: 14))
                context.fill(Path(ellipseIn: CGRect(x: sun.x - 7, y: sun.y - 7, width: 14, height: 14)), with: .color(gold))
            } else {
                var moon = context.resolve(Image(systemName: "moon.fill"))
                moon.shading = .color(.white.opacity(0.92))
                context.draw(moon, in: CGRect(x: center.x - 8, y: base - r * 0.55 - 8, width: 16, height: 16))
            }
        }
    }

    @ViewBuilder
    private var caption: some View {
        if let times, progress != nil {
            let minutes = max(0, Int(times.sunset.timeIntervalSince(now) / 60))
            let left = Text("\(minutes / 60)h \(String(format: "%02d", minutes % 60))m")
                .foregroundStyle(Color(red: 0.95, green: 0.76, blue: 0.31))
            Text("\(left) of daylight")
        } else if times != nil {
            Text(now < span.start ? "Before sunrise" : "After sunset")
        } else {
            Text(now.formatted(date: .omitted, time: .shortened))
        }
    }

    private var accessibilityText: String {
        guard let times else { return "Time of day" }
        let rise = times.sunrise.formatted(date: .omitted, time: .shortened)
        let set = times.sunset.formatted(date: .omitted, time: .shortened)
        if progress != nil {
            let minutes = max(0, Int(times.sunset.timeIntervalSince(now) / 60))
            return "Sunrise \(rise), sunset \(set). \(minutes / 60) hours \(minutes % 60) minutes of daylight left."
        }
        return "Sunrise \(rise), sunset \(set)."
    }
}
