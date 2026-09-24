import UIKit
import ImageIO

/// Plays a small GIF with ImageIO's own animator, which decodes one frame at
/// a time instead of holding every frame: a few hundred KB per tile rather
/// than tens of MB, which is the difference between a GIF grid and a crash
/// inside a keyboard extension.
final class AnimatedImageView: UIImageView {

    /// Bumped on every play and stop; a running animation that sees a newer
    /// value stops itself, so a reused cell never shows the last one's GIF.
    private var generation = 0

    /// Wider than this and a preview is shown still, downscaled: ImageIO's
    /// animator keeps whole frames at full size, and a 512px GIF is a
    /// megabyte a frame. Providers' preview sizes are well under it.
    static let maxAnimatedPixels = 320

    func play(_ data: Data, animate: Bool, fitting side: CGFloat = 120) {
        generation += 1
        let mine = generation
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        if width > Self.maxAnimatedPixels {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: side * UIScreen.main.scale,
            ]
            if let still = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                image = UIImage(cgImage: still)
            }
            return
        }
        // The first frame at once, so a tile never flashes empty.
        if let first = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            image = UIImage(cgImage: first)
        }
        guard animate else { return }
        CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, frame, stop in
            guard let self, self.generation == mine else { stop.pointee = true; return }
            self.image = UIImage(cgImage: frame)
        }
    }

    func stop() {
        generation += 1
        image = nil
    }
}

/// Columns of different heights, each tile as tall as its GIF is for the
/// column's width, the next tile always going under the shortest column:
/// the grid of Messages' #images and of Gboard's GIF tab. Stickers use the
/// same layout with square tiles.
final class MasonryLayout: UICollectionViewLayout {

    var columns = 2 { didSet { invalidateLayout() } }
    var spacing: CGFloat = 6 { didSet { invalidateLayout() } }
    var inset = UIEdgeInsets(top: 2, left: 8, bottom: 10, right: 8) { didSet { invalidateLayout() } }
    /// Width over height of each item; square when nil.
    var aspect: ((IndexPath) -> CGFloat)?

    private var cache: [UICollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0

    override func prepare() {
        super.prepare()
        cache.removeAll()
        guard let cv = collectionView, cv.numberOfSections > 0 else { contentHeight = 0; return }
        let width = cv.bounds.width - inset.left - inset.right
        let n = max(1, columns)
        let columnWidth = (width - spacing * CGFloat(n - 1)) / CGFloat(n)
        var heights = [CGFloat](repeating: inset.top, count: n)
        for item in 0..<cv.numberOfItems(inSection: 0) {
            let ip = IndexPath(item: item, section: 0)
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let ratio = max(0.3, aspect?(ip) ?? 1)
            let height = (columnWidth / ratio).rounded()
            let attrs = UICollectionViewLayoutAttributes(forCellWith: ip)
            attrs.frame = CGRect(x: inset.left + CGFloat(column) * (columnWidth + spacing),
                                 y: heights[column], width: columnWidth, height: height)
            cache.append(attrs)
            heights[column] += height + spacing
        }
        contentHeight = (heights.max() ?? 0) + inset.bottom
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        cache.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        cache.indices.contains(indexPath.item) ? cache[indexPath.item] : nil
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }
}

/// One GIF or sticker in the grid.
final class MediaCell: UICollectionViewCell {

    let imageView = AnimatedImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private(set) var url: String?
    /// Stickers keep some air around them, as Gboard's and Apple's do; a
    /// GIF fills its tile.
    private var isSticker = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        spinner.hidesWhenStopped = true
        contentView.addSubview(spinner)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A GIF fills its rounded tile; a sticker floats on the sheet, whole.
    func configure(_ item: MediaItem, sticker: Bool) {
        url = item.preview
        isSticker = sticker
        setNeedsLayout()
        imageView.stop()
        imageView.contentMode = sticker ? .scaleAspectFit : .scaleAspectFill
        contentView.layer.cornerRadius = sticker ? 0 : 8
        contentView.backgroundColor = sticker ? .clear : Glass.surfaceCard.withAlphaComponent(0.7)
        accessibilityLabel = item.title?.isEmpty == false ? item.title : (sticker ? "Sticker" : "GIF")
        let animate = !UIAccessibility.isReduceMotionEnabled
        MediaClient.shared.previewData(item.preview) { [weak self] data in
            guard let self, self.url == item.preview, let data else { return }
            self.imageView.play(data, animate: animate,
                                fitting: max(self.bounds.width, self.bounds.height, 60))
        }
    }

    func setSending(_ sending: Bool) {
        if sending { spinner.startAnimating() } else { spinner.stopAnimating() }
        imageView.alpha = sending ? 0.45 : 1
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        url = nil
        imageView.stop()
        setSending(false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = isSticker ? contentView.bounds.insetBy(dx: 7, dy: 7) : contentView.bounds
        spinner.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
    }
}

/// One emoticon, a line of text that types as it is.
final class EmoticonCell: UICollectionViewCell {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 17)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.55
        label.textColor = Glass.textPrimary
        contentView.addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds.insetBy(dx: 4, dy: 0)
    }
    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? Glass.fillSoft : .clear
            contentView.layer.cornerRadius = 8
        }
    }
}

/// Glyphs for the board's mode switch that SF Symbols does not have.
enum BoardGlyphs {

    /// A sticker: a rounded square with its corner peeling, and a smile.
    static func sticker(side: CGFloat = 17) -> UIImage {
        let size = CGSize(width: side + 2, height: side + 2)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let s = side, o: CGFloat = 1, r = s * 0.24, fold = s * 0.36
            let path = UIBezierPath()
            path.move(to: CGPoint(x: o + r, y: o))
            path.addLine(to: CGPoint(x: o + s - r, y: o))
            path.addQuadCurve(to: CGPoint(x: o + s, y: o + r), controlPoint: CGPoint(x: o + s, y: o))
            path.addLine(to: CGPoint(x: o + s, y: o + s - fold))
            path.addLine(to: CGPoint(x: o + s - fold, y: o + s))
            path.addLine(to: CGPoint(x: o + r, y: o + s))
            path.addQuadCurve(to: CGPoint(x: o, y: o + s - r), controlPoint: CGPoint(x: o, y: o + s))
            path.addLine(to: CGPoint(x: o, y: o + r))
            path.addQuadCurve(to: CGPoint(x: o + r, y: o), controlPoint: CGPoint(x: o, y: o))
            path.close()
            // The peeled corner, folded back over the face.
            path.move(to: CGPoint(x: o + s, y: o + s - fold))
            path.addQuadCurve(to: CGPoint(x: o + s - fold, y: o + s),
                              controlPoint: CGPoint(x: o + s - fold * 0.95, y: o + s - fold * 0.95))
            // The smile and the eyes.
            path.move(to: CGPoint(x: o + s * 0.28, y: o + s * 0.56))
            path.addQuadCurve(to: CGPoint(x: o + s * 0.60, y: o + s * 0.62),
                              controlPoint: CGPoint(x: o + s * 0.42, y: o + s * 0.78))
            UIColor.black.setStroke()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
            UIColor.black.setFill()
            for x in [0.34, 0.60] {
                UIBezierPath(ovalIn: CGRect(x: o + s * x - 1.1, y: o + s * 0.34, width: 2.2, height: 2.6)).fill()
            }
        }.withRenderingMode(.alwaysTemplate)
    }

    /// A word as a glyph ("GIF", ":-)"), for places that take an image.
    static func text(_ string: String, size: CGFloat = 13, weight: UIFont.Weight = .bold,
                     boxed: Bool = false) -> UIImage {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let text = (string as NSString).size(withAttributes: attrs)
        let pad: CGFloat = boxed ? 3 : 0
        let canvas = CGSize(width: ceil(text.width) + pad * 2 + 2, height: ceil(text.height) + 2)
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            if boxed {
                let box = UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvas).insetBy(dx: 0.75, dy: 1.5),
                                       cornerRadius: 3)
                box.lineWidth = 1.4
                UIColor.black.setStroke()
                box.stroke()
            }
            (string as NSString).draw(at: CGPoint(x: pad + 1, y: 1), withAttributes: attrs)
        }.withRenderingMode(.alwaysTemplate)
    }
}
