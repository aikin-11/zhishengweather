import SwiftUI

@main
struct ZhishengWeatherApp: App {
    @StateObject private var model = WeatherViewModel()

    var body: some Scene {
        WindowGroup {
            WeatherHomeView(model: model)
                .preferredColorScheme(.dark)
                .task { await model.refresh() }
        }
    }
}

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var city = UserDefaults.standard.string(forKey: "weather.city") ?? "北京"
    @Published var weather: ForecastResponse?
    @Published var air: AirResponse?
    @Published var matches: [GeoResult] = []
    @Published var isLoading = false
    @Published var error: String?

    private var coordinate: (Double, Double) {
        UserDefaults.standard.string(forKey: "weather.coordinate")
            .flatMap { value in
                let pieces = value.split(separator: ",").compactMap { Double($0) }
                return pieces.count == 2 ? (pieces[0], pieces[1]) : nil
            } ?? (39.9042, 116.4074)
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        let (lat, lon) = coordinate
        do {
            async let forecast = WeatherAPI.forecast(lat: lat, lon: lon)
            async let airQuality = WeatherAPI.air(lat: lat, lon: lon)
            weather = try await forecast
            air = try? await airQuality
        } catch {
            self.error = "天气加载失败，请检查网络后重试。"
        }
    }

    func search(_ query: String) async {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
            matches = []
            return
        }
        do { matches = try await WeatherAPI.search(query) }
        catch { matches = [] }
    }

    func select(_ result: GeoResult) {
        city = result.displayName
        UserDefaults.standard.set(city, forKey: "weather.city")
        UserDefaults.standard.set("\(result.latitude),\(result.longitude)", forKey: "weather.coordinate")
        matches = []
        Task { await refresh() }
    }
}

private enum WeatherAPI {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func forecast(lat: Double, lon: Double) async throws -> ForecastResponse {
        try await get("https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,surface_pressure,wind_speed_10m,wind_direction_10m,visibility,uv_index&hourly=temperature_2m,precipitation_probability,weather_code&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max,sunrise,sunset&forecast_days=7&forecast_hours=24&timezone=auto")
    }

    static func air(lat: Double, lon: Double) async throws -> AirResponse {
        try await get("https://air-quality-api.open-meteo.com/v1/air-quality?latitude=\(lat)&longitude=\(lon)&current=pm10,pm2_5,us_aqi&timezone=auto")
    }

    static func search(_ query: String) async throws -> [GeoResult] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "8"), URLQueryItem(name: "language", value: "zh"), URLQueryItem(name: "format", value: "json")]
        return try await get(components.url!.absoluteString, as: GeoResponse.self).results ?? []
    }

    private static func get<T: Decodable>(_ string: String, as type: T.Type = T.self) async throws -> T {
        guard let url = URL(string: string) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try decoder.decode(T.self, from: data)
    }
}

struct ForecastResponse: Decodable {
    let current: CurrentWeather?
    let hourly: HourlyWeather?
    let daily: DailyWeather?
}
struct CurrentWeather: Decodable {
    let temperature2m: Double?
    let apparentTemperature: Double?
    let relativeHumidity2m: Int?
    let weatherCode: Int?
    let windSpeed10m: Double?
    let windDirection10m: Int?
    let surfacePressure: Double?
    let uvIndex: Double?
}
struct HourlyWeather: Decodable { let time: [String]?; let temperature2m: [Double]?; let precipitationProbability: [Int]?; let weatherCode: [Int]? }
struct DailyWeather: Decodable { let time: [String]?; let temperature2mMax: [Double]?; let temperature2mMin: [Double]?; let weatherCode: [Int]?; let precipitationProbabilityMax: [Int]? }
struct AirResponse: Decodable { let current: AirCurrent? }
struct AirCurrent: Decodable { let usAqi: Int?; let pm2_5: Double?; let pm10: Double? }
struct GeoResponse: Decodable { let results: [GeoResult]? }
struct GeoResult: Decodable, Identifiable {
    let id: Int
    let name: String
    let admin1: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    var displayName: String { [name, admin1, country].compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: " · ") }
}

enum WeatherCode {
    static func label(_ code: Int?) -> String {
        guard let code else { return "天气" }
        switch code {
        case 0: return "晴朗"
        case 1: return "大致晴朗"
        case 2: return "局部多云"
        case 3: return "阴天"
        case 45, 48: return "雾"
        case 51, 53, 55: return "毛毛雨"
        case 61, 63, 65: return "降雨"
        case 71, 73, 75, 77: return "降雪"
        case 80, 81, 82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95, 96, 99: return "雷暴"
        default: return "天气"
        }
    }
    static func symbol(_ code: Int?) -> String {
        guard let code else { return "cloud.fill" }
        switch code {
        case 0, 1: return "sun.max.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
