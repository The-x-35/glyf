import UIKit

/// Thumbnails for search result cards.
///
/// A keyboard extension gets a fraction of an app's memory budget, so this
/// deliberately stays small: a hard cap on entries, downscaled decodes, and
/// everything dropped on a memory warning. A missed thumbnail is a blank
/// corner, never a crash.
enum ThumbLoader {

    private static let cache = NSCache<NSString, UIImage>()
    private static var inFlight: [String: [(UIImage?) -> Void]] = [:]
    private static var configured = false

    private static func configure() {
        guard !configured else { return }
        configured = true
        cache.countLimit = 40
        // ~64px² RGBA ≈ 16KB each; a Short's tall frame ≈ 0.45MB, so 6MB keeps
        // a shelf of ten and the small ones beside it.
        cache.totalCostLimit = 6 * 1024 * 1024
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { _ in cache.removeAllObjects() }
    }

    static func cached(_ urlString: String, variant: String = "") -> UIImage? {
        configure()
        return cache.object(forKey: (urlString + variant) as NSString)
    }

    /// Loads and downscales to `maxPixel` on the long edge. The completion
    /// runs on the main queue, once, and may be called synchronously when the
    /// image is already cached.
    ///
    /// `crop` cuts the decoded picture (in its pixels) before it is kept, so
    /// only what is shown stays in memory; `variant` names that cut in the
    /// cache key.
    static func load(_ urlString: String, maxPixel: CGFloat = 160,
                     variant: String = "", crop: ((CGSize) -> CGRect)? = nil,
                     completion: @escaping (UIImage?) -> Void) {
        configure()
        let key = urlString + variant
        if let hit = cache.object(forKey: key as NSString) {
            completion(hit); return
        }
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            completion(nil); return
        }
        if inFlight[key] != nil {
            inFlight[key]?.append(completion); return
        }
        inFlight[key] = [completion]

        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        // Our own server's pictures (a place's photo, its map) sit behind the
        // sign-in like every other call; no one else ever gets the session.
        if let own = URL(string: SettingsStore.current.backendURL)?.host, url.host == own {
            req.glyfSession()
        }
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var image = data.flatMap { downscale($0, maxPixel: maxPixel) }
            if let crop, let cg = image?.cgImage {
                // Redrawn, not `cropping(to:)`: a cropped CGImage keeps the
                // whole decoded picture alive behind it.
                let rect = crop(CGSize(width: cg.width, height: cg.height)).integral
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = 1
                image = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
                    UIImage(cgImage: cg).draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
                }
            }
            DispatchQueue.main.async {
                if let image {
                    let cost = Int(image.size.width * image.size.height * 4)
                    cache.setObject(image, forKey: key as NSString, cost: cost)
                }
                let waiting = inFlight.removeValue(forKey: key) ?? []
                for block in waiting { block(image) }
            }
        }.resume()
    }

    /// Decodes straight to the display size — a full-resolution decode of a
    /// YouTube thumbnail is ~1.5MB of live pixels we never show.
    private static func downscale(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel * UIScreen.main.scale,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}
