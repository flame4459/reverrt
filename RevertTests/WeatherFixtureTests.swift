import Testing
import Foundation
@testable import Revert

@MainActor
struct WeatherFixtureTests {
    private static let valid = """
    {
      "current": { "temperature_2m": 17.4, "precipitation": 0.0, "weather_code": 61 },
      "hourly": { "precipitation_probability": [10, 55, 80, 20] }
    }
    """

    @Test func parsesACurrentForecast() throws {
        let weather = try #require(CompanionWeatherService.parse(Data(Self.valid.utf8)))
        #expect(weather.condition == "Rain")
        #expect(abs(weather.temperatureC - 17.4) < 0.001)
        #expect(weather.precipitationChance == 55)
        #expect(weather.summary.contains("Rain"))
    }

    @Test func malformedPayloadsAreRejected() {
        #expect(CompanionWeatherService.parse(Data()) == nil)
        #expect(CompanionWeatherService.parse(Data("{}".utf8)) == nil)
        #expect(CompanionWeatherService.parse(Data("<html>429</html>".utf8)) == nil)
        #expect(CompanionWeatherService.parse(Data(#"{"current":{}}"#.utf8)) == nil)
        #expect(CompanionWeatherService.parse(Data(#"{"current":{"temperature_2m":1},"hourly":{}}"#.utf8)) == nil)
    }

    @Test func unknownWeatherCodesFallBack() throws {
        let data = Data(#"{"current":{"temperature_2m":5,"precipitation":0,"weather_code":9999},"hourly":{"precipitation_probability":[0]}}"#.utf8)
        let weather = try #require(CompanionWeatherService.parse(data))
        #expect(weather.condition == "Mixed skies")
        #expect(weather.precipitationChance == 0)
    }
}
