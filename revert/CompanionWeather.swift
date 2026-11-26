import Foundation
import CoreLocation

nonisolated struct CompanionWeather: Sendable, Equatable {
    let condition: String
    let temperatureC: Double
    let precipitationNowMM: Double
    let precipitationChance: Int

    var summary: String {
        let rain: String
        if precipitationNowMM > 0.05 {
            rain = "Rain now."
        } else if precipitationChance >= 40 {
            rain = "Showers possible within two hours."
        } else {
            rain = "Dry for two hours."
        }
        return "\(condition), \(Units.temperatureText(temperatureC)). \(rain)"
    }

    static func condition(for code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1, 2, 3: "Cloudy"
        case 45, 48: "Fog"
        case 51, 53, 55, 56, 57: "Drizzle"
        case 61, 63, 65, 66, 67: "Rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Showers"
        case 95, 96, 99: "Thunderstorms"
        default: "Mixed skies"
        }
    }
}

/// Small Open-Meteo reader for the companion. No account and no Revert
/// backend; only the rounded route-start coordinate is sent. Failure is silent
/// and the companion says it has no feed rather than guessing.
actor CompanionWeatherService {
    static let shared = CompanionWeatherService()

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let precipitation: Double
            let weather_code: Int
        }
        struct Hourly: Decodable {
            let precipitation_probability: [Int]
        }
        let current: Current
        let hourly: Hourly
    }

    private var cache: [String: (date: Date, weather: CompanionWeather)] = [:]

    func weather(for coordinate: CLLocationCoordinate2D) async -> CompanionWeather? {
        let key = String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
        if let cached = cache[key], Date().timeIntervalSince(cached.date) < 600 {
            return cached.weather
        }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,precipitation,weather_code"),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            // The next two hours, not the first two entries of a whole day.
            URLQueryItem(name: "forecast_hours", value: "2"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let weather = Self.parse(data) else { return nil }
            cache[key] = (Date(), weather)
            return weather
        } catch {
            return nil
        }
    }

    /// Pure decoder, so a fixture can prove the payload shape without a network.
    nonisolated static func parse(_ data: Data) -> CompanionWeather? {
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let chance = decoded.hourly.precipitation_probability.prefix(2).max() ?? 0
        return CompanionWeather(
            condition: CompanionWeather.condition(for: decoded.current.weather_code),
            temperatureC: decoded.current.temperature_2m,
            precipitationNowMM: decoded.current.precipitation,
            precipitationChance: chance
        )
    }
}
