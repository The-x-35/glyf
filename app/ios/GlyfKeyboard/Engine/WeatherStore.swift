import Foundation

/// Today's and tomorrow's weather where the phone last was, from Open-Meteo
/// (free, keyless, already the server's weather source), fetched by the
/// keyboard when a message asks about the weather and kept for 30 minutes.
/// WeatherStore.kt is Android's twin.
final class WeatherStore {
    static let shared = WeatherStore()
    private var loading = false
    private static let ttl: TimeInterval = 30 * 60

    func ensure(lat: Double, lon: Double, fahrenheit: Bool, then: @escaping () -> Void) {
        if let w = Smart.weather, Date().timeIntervalSince(w.at) < Self.ttl, w.fahrenheit == fahrenheit { return }
        guard !loading, var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else { return }
        comps.queryItems = [
            // About a kilometre, as the privacy policy says, and no more.
            URLQueryItem(name: "latitude", value: String(format: "%.2f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,precipitation"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ] + (fahrenheit ? [URLQueryItem(name: "temperature_unit", value: "fahrenheit")] : [])
        guard let url = comps.url else { return }
        loading = true
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            let obj = (response as? HTTPURLResponse)?.statusCode == 200
                ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
            let snapshot = obj.flatMap { Self.parse($0, fahrenheit: fahrenheit) }
            DispatchQueue.main.async {
                self?.loading = false
                guard let snapshot else { return }
                Smart.weather = snapshot
                then()
            }
        }.resume()
    }

    static func parse(_ obj: [String: Any], fahrenheit: Bool, at: Date = Date()) -> Smart.WeatherSnapshot? {
        guard let current = obj["current"] as? [String: Any], let daily = obj["daily"] as? [String: Any] else { return nil }
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        func doubles(_ k: String) -> [Double] { (daily[k] as? [Any])?.compactMap(num) ?? [] }
        guard let t = num(current["temperature_2m"]) else { return nil }
        let w = Smart.WeatherSnapshot(
            at: at, fahrenheit: fahrenheit, nowTemp: t, nowCode: Int(num(current["weather_code"]) ?? 0),
            nowRain: num(current["precipitation"]) ?? 0,
            high: doubles("temperature_2m_max"), low: doubles("temperature_2m_min"),
            rainChance: doubles("precipitation_probability_max").map { Int($0.rounded()) },
            code: doubles("weather_code").map { Int($0) })
        return w.high.isEmpty ? nil : w
    }
}
