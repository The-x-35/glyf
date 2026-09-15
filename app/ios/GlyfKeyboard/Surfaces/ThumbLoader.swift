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
        // ~64px² RGBA ≈ 16KB each; 4MB is a generous ceiling for 40 of them.
        cache.totalCostLimit = 4 * 1024 * 1024
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { _ in cache.removeAllObjects() }
    }

    static func cached(_ urlString: String) -> UIImage? {
        configure()
        return cache.object(forKey: urlString as NSString)
    }

    /// Loads and downscales to `maxPixel` on the long edge. The completion
    /// runs on the main queue, once, and may be called synchronously when the
    /// image is already cached.
    static func load(_ urlString: String, maxPixel: CGFloat = 160,
                     completion: @escaping (UIImage?) -> Void) {
        configure()
        if let hit = cache.object(forKey: urlString as NSString) {
            completion(hit); return
        }
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            completion(nil); return
        }
        if inFlight[urlString] != nil {
            inFlight[urlString]?.append(completion); return
        }
        inFlight[urlString] = [completion]

        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let image = data.flatMap { downscale($0, maxPixel: maxPixel) }
            DispatchQueue.main.async {
                if let image {
                    let cost = Int(image.size.width * image.size.height * 4)
                    cache.setObject(image, forKey: urlString as NSString, cost: cost)
                }
                let waiting = inFlight.removeValue(forKey: urlString) ?? []
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
