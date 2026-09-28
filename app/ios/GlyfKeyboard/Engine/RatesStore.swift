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
    /// The token behind each cashtag, so Buy knows what to buy.
    private(set) var mints: [String: String] = [:]
    /// The market's ticker for what was typed ("APPL": "AAPL").
    private(set) var tickers: [String: String] = [:]
    private var cryptoAt: [String: Date] = [:]
    /// Copied or typed addresses: a wallet, or the token at that address.
    private(set) var addresses: [String: Smart.AddressKind] = [:]
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
        Smart.RatesSnapshot(fiat: fiat, crypto: crypto, local: local, mints: mints, addresses: addresses,
                            tickers: tickers)
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
                self.mints[symbol] = quote["mint"] as? String
                self.tickers[symbol] = quote["ticker"] as? String
            } else {
                self.crypto.removeValue(forKey: symbol)
                self.mints.removeValue(forKey: symbol)
                self.tickers.removeValue(forKey: symbol)
            }
            then()
        }
    }

    /// Whether an address is a token's (and which) or someone's wallet.
    /// Asked once per address; when the answer can't be had it counts as a
    /// wallet, and the app checks again before any money moves.
    func ensureAddress(_ address: String, then: @escaping () -> Void) {
        guard addresses[address] == nil else { return }
        fetch(path: "/rates/token?mint=\(address)", key: "address:\(address)", always: true) { [weak self] obj in
            guard let self else { return }
            if let token = obj?["token"] as? [String: Any], let symbol = token["symbol"] as? String {
                self.addresses[address] = .token(symbol: symbol, usd: token["usd"] as? Double)
            } else {
                self.addresses[address] = .wallet
            }
            then()
        }
    }

    private func fetch(path: String, key: String, done: @escaping ([String: Any]) -> Void) {
        fetch(path: path, key: key, always: false) { obj in if let obj { done(obj) } }
    }

    /// `always` hands a failure on as nil rather than dropping it.
    private func fetch(path: String, key: String, always: Bool, done: @escaping ([String: Any]?) -> Void) {
        guard !inFlight.contains(key),
              let url = URL(string: "\(SettingsStore.current.backendURL)\(path)") else { return }
        inFlight.insert(key)
        var req = URLRequest(url: url)
        req.glyfSession()
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                self?.inFlight.remove(key)
                let obj = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                guard let obj, obj["ok"] as? Bool == true else {
                    if always { done(nil) }
                    return
                }
                done(obj)
            }
        }.resume()
    }
}
