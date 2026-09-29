import Foundation

// MARK: - Weather history for every logged shift
//
// Same-day shifts saved from the wizard get the live reading (then its daily
// high) the moment they're saved. Everything else — a backdated shift, a
// live-shift clock-out, a Siri entry — used to get no weather at all. This
// fills the gap: whenever a work shift is added without weather, look up that
// day's high and dominant condition from Open-Meteo (the provider the app
// already uses) and attach it.
//
// Location: the shift's own coordinates when it has them, otherwise the
// device's last known position. No location permission and no coordinates →
// no lookup; the app never asks for location just for this.

extension WeatherService {
    /// Daily high temperature and dominant WMO condition for `day` at a
    /// coordinate. Recent days (and up to two weeks ahead) come from the
    /// forecast API; anything older than ~2 months from the archive API.
    nonisolated static func dailySnapshot(
        for day: Date,
        latitude: Double,
        longitude: Double,
        locality: String,
        calendar: Calendar = .current
    ) async throws -> WeatherSnapshot {
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: day)
        let daysAgo = calendar.dateComponents([.day], from: target, to: today).day ?? 0
        guard daysAgo >= -14 else { throw URLError(.unsupportedURL) } // beyond forecast range

        let base = daysAgo > 60
            ? "https://archive-api.open-meteo.com/v1/archive"
            : "https://api.open-meteo.com/v1/forecast"
        let dayString = isoDay(target, calendar: calendar)
        var components = URLComponents(string: base)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,weather_code"),
            URLQueryItem(name: "start_date", value: dayString),
            URLQueryItem(name: "end_date", value: dayString),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(DailyHistoryResponse.self, from: data)
        guard let high = decoded.daily.temperature_2m_max.first ?? nil,
              let code = decoded.daily.weather_code.first ?? nil else {
            throw URLError(.cannotParseResponse)
        }
        return WeatherSnapshot(
            temperatureC: high,
            code: code,
            isDay: true,
            locality: locality,
            fetchedAt: Date(),
            latitude: latitude,
            longitude: longitude
        )
    }

    // nonisolated: decoded inside the nonisolated `dailySnapshot`, off the
    // main actor (the target defaults to MainActor isolation).
    nonisolated private struct DailyHistoryResponse: Decodable {
        nonisolated struct Daily: Decodable {
            // Optional elements: the archive returns null for days it
            // doesn't have yet (its data trails by a few days).
            let temperature_2m_max: [Double?]
            let weather_code: [Int?]
        }
        let daily: Daily
    }

    private nonisolated static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

@MainActor
extension HoursStore {
    /// Attaches the day's weather to a newly added work shift that has none.
    /// Fire-and-forget: a failed lookup leaves the shift exactly as saved.
    func attachWeatherIfMissing(_ entry: WorkEntry) {
        guard !entry.isOffDay, entry.weather == nil else { return }
        let coordinate: (lat: Double, lon: Double, locality: String)?
        if let lat = entry.latitude, let lon = entry.longitude {
            coordinate = (lat, lon, WeatherService.shared.snapshot?.locality ?? "")
        } else if let last = WeatherService.shared.snapshot {
            coordinate = (last.latitude, last.longitude, last.locality)
        } else {
            coordinate = nil
        }
        guard let coordinate else { return }

        let entryID = entry.id
        let day = entry.date
        Task { @MainActor [weak self] in
            guard let snapshot = try? await WeatherService.dailySnapshot(
                for: day,
                latitude: coordinate.lat,
                longitude: coordinate.lon,
                locality: coordinate.locality
            ) else { return }
            // Re-read: the shift may have been edited, deleted, or given
            // weather by another path while the request was in flight.
            guard let self,
                  var stored = self.entries.first(where: { $0.id == entryID }),
                  stored.weather == nil else { return }
            stored.weather = snapshot
            self.update(stored)
        }
    }
}
