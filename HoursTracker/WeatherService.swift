import Foundation
import Combine
import os
import CoreLocation
import SwiftUI

// MARK: - Snapshot

/// One "right now" reading for the Today card. Temperature is stored in
/// Celsius and formatted per the device locale at display time, so US users
/// see °F without a setting.
struct WeatherSnapshot: Codable, Equatable {
    let temperatureC: Double
    /// WMO weather interpretation code (Open-Meteo's `weather_code`).
    let code: Int
    let isDay: Bool
    let locality: String
    let fetchedAt: Date
    let latitude: Double
    let longitude: Double

    var temperatureText: String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        let celsius = Measurement(value: temperatureC, unit: UnitTemperature.celsius)
        let local = Locale.current.measurementSystem == .metric
            ? celsius
            : celsius.converted(to: .fahrenheit)
        return formatter.string(from: local)
    }

    /// SF Symbol for the condition; night variants where one exists.
    var symbolName: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    var conditionText: String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Cloudy"
        }
    }
}

// MARK: - Service

/// Local weather for the Home card: asks for when-in-use location only when
/// the user taps in, then reads Open-Meteo (keyless) for the current
/// conditions. The last reading is cached so the card paints instantly on
/// launch and only refetches once it's stale.
@MainActor
final class WeatherService: NSObject, ObservableObject {
    static let shared = WeatherService()

    enum Status: Equatable {
        /// Location permission hasn't been asked for yet.
        case needsPermission
        case denied
        case loading
        case loaded
        case failed
    }

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var status: Status = .needsPermission

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private static let cacheKey = "weather_snapshot_v1"
    private static let staleAfter: TimeInterval = 30 * 60
    private var fetchTask: Task<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(WeatherSnapshot.self, from: data) {
            snapshot = cached
            status = .loaded
        }
        syncStatusWithAuthorization()
    }

    /// Called when the user taps the weather row before permission exists.
    func requestPermission() {
        guard manager.authorizationStatus == .notDetermined else {
            refreshIfNeeded(force: true)
            return
        }
        status = .loading
        manager.requestWhenInUseAuthorization()
    }

    /// Refreshes when the cached reading is stale (or `force`). Safe to call
    /// on every Home appearance.
    func refreshIfNeeded(force: Bool = false) {
        guard isAuthorized else {
            syncStatusWithAuthorization()
            return
        }
        if !force, let snapshot, Date().timeIntervalSince(snapshot.fetchedAt) < Self.staleAfter {
            status = .loaded
            return
        }
        if snapshot == nil { status = .loading }
        manager.requestLocation()
    }

    private var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    private func syncStatusWithAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            if snapshot == nil { status = .needsPermission }
        case .denied, .restricted:
            status = .denied
        default:
            if snapshot == nil { status = .loading }
        }
    }

    private func fetch(at location: CLLocation) {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let reading = try await Self.currentConditions(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                let locality = await self.locality(for: location)
                let snapshot = WeatherSnapshot(
                    temperatureC: reading.temperature,
                    code: reading.code,
                    isDay: reading.isDay,
                    locality: locality,
                    fetchedAt: Date(),
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                guard !Task.isCancelled else { return }
                self.snapshot = snapshot
                self.status = .loaded
                if let data = try? JSONEncoder().encode(snapshot) {
                    UserDefaults.standard.set(data, forKey: Self.cacheKey)
                }
            } catch {
                AppLogger.network.warning("Weather fetch failed: \(error.localizedDescription, privacy: .public)")
                // A stale reading beats an error state on the card.
                self.status = self.snapshot == nil ? .failed : .loaded
            }
        }
    }

    private func locality(for location: CLLocation) async -> String {
        // Reuse the cached name when we haven't moved meaningfully — the
        // geocoder is rate-limited and the town rarely changes between reads.
        if let snapshot,
           CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
               .distance(from: location) < 2_000,
           !snapshot.locality.isEmpty {
            return snapshot.locality
        }
        let placemarks = try? await geocoder.reverseGeocodeLocation(location)
        return placemarks?.first?.locality ?? ""
    }

    /// Fetches today's forecast high and returns a snapshot for logging
    /// against a shift — same condition/locality as the current reading,
    /// but the day's max instead of the instant-in-time temperature.
    func dailyHighSnapshot(for current: WeatherSnapshot) async -> WeatherSnapshot {
        do {
            let high = try await Self.todayHighTemperature(
                latitude: current.latitude, longitude: current.longitude
            )
            return WeatherSnapshot(
                temperatureC: high,
                code: current.code,
                isDay: current.isDay,
                locality: current.locality,
                fetchedAt: current.fetchedAt,
                latitude: current.latitude,
                longitude: current.longitude
            )
        } catch {
            AppLogger.network.warning("Daily-high fetch failed: \(error.localizedDescription, privacy: .public)")
            return current
        }
    }

    // MARK: Open-Meteo

    private struct Reading {
        let temperature: Double
        let code: Int
        let isDay: Bool
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        let current: Current
    }

    private static func currentConditions(latitude: Double, longitude: Double) async throws -> Reading {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return Reading(
            temperature: decoded.current.temperature_2m,
            code: decoded.current.weather_code,
            isDay: decoded.current.is_day == 1
        )
    }

    private struct OpenMeteoDailyResponse: Decodable {
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
        }
        let daily: Daily
    }

    private static func todayHighTemperature(latitude: Double, longitude: Double) async throws -> Double {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_max"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenMeteoDailyResponse.self, from: data)
        guard let high = decoded.daily.temperature_2m_max.first else {
            throw URLError(.cannotParseResponse)
        }
        return high
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.syncStatusWithAuthorization()
            self.refreshIfNeeded(force: self.snapshot == nil)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.fetch(at: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            AppLogger.network.warning("Weather location failed: \(error.localizedDescription, privacy: .public)")
            // Fall back to the last known coordinates if we have any.
            if let snapshot = self.snapshot {
                self.fetch(at: CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude))
            } else {
                self.status = .failed
            }
        }
    }
}
