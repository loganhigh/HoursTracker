import SwiftUI
import Combine
import CoreLocation

// MARK: - Weather Data

struct WeatherData {
    let location: String
    let temperature: Double
    let high: Double
    let low: Double
    let humidity: Double
    let windKph: Double
    let conditionCode: Int
    let isDay: Bool

    var condition: String {
        switch conditionCode {
        case 0: return "Clear Sky"
        case 1: return "Mainly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow Grains"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with Hail"
        default: return "Unknown"
        }
    }

    var icon: String {
        switch conditionCode {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.min.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

// MARK: - Weather Service

@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    @Published var weather: WeatherData?
    @Published var isLoading = false

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastFetch: Date?

    func fetchIfNeeded() {
        if let last = lastFetch, Date().timeIntervalSince(last) < 1800 { return }
        guard !isLoading else { return }
        isLoading = true

        locationManager.requestWhenInUseAuthorization()
        guard let location = locationManager.location else {
            isLoading = false
            return
        }

        Task {
            await fetch(location: location)
        }
    }

    private func fetch(location: CLLocation) async {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let cityName = await resolveCity(location: location)

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,is_day,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min&temperature_unit=celsius&wind_speed_unit=kmh&timezone=auto&forecast_days=1"

        guard let url = URL(string: urlString) else {
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let current = json["current"] as? [String: Any],
               let daily = json["daily"] as? [String: Any] {
                let temp = current["temperature_2m"] as? Double ?? 0
                let humidity = (current["relative_humidity_2m"] as? Double ?? 0) / 100
                let windKph = current["wind_speed_10m"] as? Double ?? 0
                let code = current["weather_code"] as? Int ?? 0
                let isDay = (current["is_day"] as? Int ?? 1) == 1
                let highs = daily["temperature_2m_max"] as? [Double] ?? []
                let lows = daily["temperature_2m_min"] as? [Double] ?? []

                weather = WeatherData(
                    location: cityName,
                    temperature: temp,
                    high: highs.first ?? temp,
                    low: lows.first ?? temp,
                    humidity: humidity,
                    windKph: windKph,
                    conditionCode: code,
                    isDay: isDay
                )
                lastFetch = Date()
            }
        } catch {
            #if DEBUG
            print("Weather fetch error: \(error.localizedDescription)")
            #endif
        }
        isLoading = false
    }

    private func resolveCity(location: CLLocation) async -> String {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.locality ?? "Your Location"
        } catch {
            return "Your Location"
        }
    }
}

// MARK: - Weather Card View

struct WeatherCard: View {
    let prestige: Int
    @StateObject private var service = WeatherService.shared

    private var tier: PrestigeTheme.Tier {
        PrestigeTheme.tier(for: prestige)
    }

    var body: some View {
        Group {
            if let weather = service.weather {
                weatherContent(weather)
            } else if service.isLoading {
                loadingContent
            }
        }
        .onAppear {
            service.fetchIfNeeded()
        }
    }

    private func weatherContent(_ weather: WeatherData) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(weather.location)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.text)

                    Text(weather.condition)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Image(systemName: weather.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: tier.gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("\(Int(round(weather.temperature)))°")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.text)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                statPill(label: "H", value: "\(Int(round(weather.high)))°")
                statPill(label: "L", value: "\(Int(round(weather.low)))°")
                statPill(label: "💧", value: "\(Int(round(weather.humidity * 100)))%")
                statPill(label: "💨", value: "\(Int(round(weather.windKph)))kph")
            }
            .padding(.top, 12)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tier.primary.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.Colors.faint)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.Colors.bg.opacity(0.6))
        )
    }

    private var loadingContent: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(tier.primary)
            Text("Loading weather…")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                )
        )
    }
}
