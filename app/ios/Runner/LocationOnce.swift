import CoreLocation

/// One coarse location fix, on demand.
///
/// The keyboard extension cannot ask for location itself, so the app asks
/// during onboarding and caches the result in the App Group for the keyboard
/// to read. This deliberately takes a single reduced-accuracy fix and then
/// stops the manager — Glyf never tracks, and nothing here runs in the
/// background.
final class LocationOnce: NSObject, CLLocationManagerDelegate {

    static let shared = LocationOnce()

    enum Outcome {
        case fix(lat: Double, lon: Double)
        case denied
        case failed
    }

    private let manager = CLLocationManager()
    private var pending: ((Outcome) -> Void)?
    private var timeout: DispatchWorkItem?

    override init() {
        super.init()
        manager.delegate = self
        // Neighbourhood-level is all "coffee near me" needs, and it returns
        // faster and costs far less battery than a precise fix.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorization: String {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "granted"
        case .notDetermined: return "notDetermined"
        default: return "denied"
        }
    }

    /// Asks for permission if needed, then delivers one fix. The completion
    /// runs on the main queue exactly once.
    func request(_ completion: @escaping (Outcome) -> Void) {
        guard pending == nil else { completion(.failed); return }
        pending = completion

        switch manager.authorizationStatus {
        case .denied, .restricted:
            finish(.denied)
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            start()
        }
    }

    private func start() {
        // A stuck fix must not leave onboarding waiting forever.
        let work = DispatchWorkItem { [weak self] in self?.finish(.failed) }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
        manager.requestLocation()
    }

    private func finish(_ outcome: Outcome) {
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        guard let block = pending else { return }
        pending = nil
        DispatchQueue.main.async { block(outcome) }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pending != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: start()
        case .denied, .restricted: finish(.denied)
        case .notDetermined: break            // still waiting on the prompt
        @unknown default: finish(.failed)
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { finish(.failed); return }
        // Rounded to ~1km: enough for "near me", too coarse to identify a home.
        finish(.fix(lat: (c.latitude * 100).rounded() / 100,
                    lon: (c.longitude * 100).rounded() / 100))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failed)
    }
}
