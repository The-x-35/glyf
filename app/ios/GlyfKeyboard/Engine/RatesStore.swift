import Foundation

/// The rates behind the money chip, fetched from the server (which caches
/// the ECB and Jupiter for everyone) and kept in the App Group so a fresh
/// keyboard process has yesterday's table before its first request lands.
/// Fiat is asked for once an hour; a token once a minute, and only for the
/// ticker on screen.
final class RatesStore {
    static let shared = RatesStore()

    private(set) var fiat: [String: Double] = [:]
    private var fiatAt: Date?
    private(set) var crypto: [String: Double] = [:]
    private var cryptoAt: [String: Date] = [:]
    private var inFlight = Set<String>()

    private static let file = "rates.json"
    private static let fiatTTL: TimeInterval = 60 * 60
    private static let tokenTTL: TimeInterval = 60

    private init() {
        if let saved = AppGroupStore.readJSON(name: Self.file) {
            fiat = (saved["fiat"] as? [String: Double]) ?? [:]
            if let at = saved["fiatAt"] as? Double { fiatAt = Date(timeIntervalSince1970: at) }
        }
    }

    /// The currency money converts into: the one the person chose in the
    /// app; otherwise where the phone is — the region the app recorded
    /// (it knows from onboarding), then the locale.
    var local: String {
        if let chosen = SettingsStore.current.moneyCurrency?.uppercased(),
           chosen != "AUTO", chosen.count == 3 { return chosen }
        if let region = SettingsStore.current.region?.uppercased(),
           let code = Self.regionCurrency[region] { return code }
        if #available(iOS 16, *), let code = Locale.current.currency?.identifier { return code }
        return "USD"
    }

    private static let regionCurrency: [String: String] = [
        "IN": "INR", "US": "USD", "GB": "GBP", "JP": "JPY", "SG": "SGD", "AU": "AUD",
        "CA": "CAD", "AE": "AED", "CH": "CHF", "CN": "CNY", "HK": "HKD", "KR": "KRW",
        "DE": "EUR", "FR": "EUR", "ES": "EUR", "IT": "EUR", "NL": "EUR", "IE": "EUR",
        "PT": "EUR", "AT": "EUR", "BE": "EUR", "FI": "EUR", "GR": "EUR",
    ]

    func snapshot() -> Smart.RatesSnapshot {
        Smart.RatesSnapshot(fiat: fiat, crypto: crypto, local: local)
    }

    /// Fetches the dollar table when it is missing or stale; `then` runs on
    /// the main queue once something new is in hand.
    func ensureFiat(then: @escaping () -> Void) {
        if let at = fiatAt, Date().timeIntervalSince(at) < Self.fiatTTL, !fiat.isEmpty { return }
        fetch(path: "/rates/fiat", key: "fiat") { [weak self] obj in
            guard let self, let rates = obj["rates"] as? [String: Double], !rates.isEmpty else { return }
            self.fiat = rates
            self.fiatAt = Date()
            _ = AppGroupStore.writeJSON(["fiat": rates, "fiatAt": Date().timeIntervalSince1970],
                                        name: Self.file)
            then()
        }
    }

    /// The dollar price of one token, refreshed after a minute.
    func ensureToken(_ symbol: String, then: @escaping () -> Void) {
        if let at = cryptoAt[symbol], Date().timeIntervalSince(at) < Self.tokenTTL { return }
        fetch(path: "/rates/crypto?symbols=\(symbol)", key: "token:\(symbol)") { [weak self] obj in
            guard let self else { return }
            // A miss is remembered too, so a made-up ticker is one request.
            self.cryptoAt[symbol] = Date()
            if let quotes = obj["quotes"] as? [String: Any],
               let quote = quotes[symbol] as? [String: Any],
               let usd = quote["usd"] as? Double {
                self.crypto[symbol] = usd
            } else {
                self.crypto.removeValue(forKey: symbol)
            }
            then()
        }
    }

    private func fetch(path: String, key: String, done: @escaping ([String: Any]) -> Void) {
        guard !inFlight.contains(key),
              let url = URL(string: "\(SettingsStore.current.backendURL)\(path)") else { return }
        inFlight.insert(key)
        var req = URLRequest(url: url)
        req.glyfSession()
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                self?.inFlight.remove(key)
                guard let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      obj["ok"] as? Bool == true else { return }
                done(obj)
            }
        }.resume()
    }
}
