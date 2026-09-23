import MapKit
import UIKit
import os.log

protocol ActSurfaceDelegate: AnyObject {
    /// Replaces the typed intent the run read with `text`.
    func actInsert(_ text: String)
    func actCopy(_ text: String)
    func actRetry()
    /// Whether ↻ makes sense now (an answer or an error is showing).
    func actRetryAvailable(_ available: Bool)
    func actClosed()
    /// A hand-off card (a search to finish elsewhere) opens instead of pasting.
    func actOpen(_ url: URL)
}

/// Hold space on what you typed → Glyf acts on it (the Acti Bar move, in
/// Glyf's language). Covers the keys the moment the hold lands:
///
///  · working — the brand keycap breathing inside quiet rings, the intent
///    quoted under it, ✕ to cancel
///  · result  — the search suite's own cards (place, list, answer, video)
///    and/or the rewritten text, with ↻ · Copy · Insert
///  · failed  — the error, tap to retry
///
/// Black pill for the primary action, hairline siblings, no purple washes:
/// the accent is only the brand dot.
final class ActSurface: UIView, UITableViewDataSource, UITableViewDelegate {

    weak var delegate: ActSurfaceDelegate?
    private let log = Logger(subsystem: "so.glyf.keyboard", category: "act")

    private enum Phase { case working, result, failed }
    private var phase: Phase = .working
    var isWorking: Bool { phase == .working }
    var hasOptions: Bool { phase == .result && !options.isEmpty }

    // Working
    private let ringsLayer = CALayer()
    private let mark = UIView()
    private let markLabel = UILabel()
    private let markDot = UIView()
    private let intentLabel = UILabel()
    /// A skill's name over its keycap while it works ("Proofread").
    private let workingTitle = UILabel()
    private let cancelButton = UIButton(type: .system)

    // Result
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let textView = UITextView()
    private let table = UITableView(frame: .zero, style: .plain)
    private let retryButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private let insertButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    private var cards: [BackendClient.SearchCard] = []
    /// A rewrite's versions, one row each, the way the website lists them.
    private var options: [BackendClient.RewriteOption] = []
    private var insertText = ""
    /// One place → a real map above its card (Apple Maps, no key needed).
    private let mapView = UIImageView()
    private var snapshotter: MKMapSnapshotter?
    private var mapPlace: BackendClient.SearchCard?

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid
        buildWorking()
        buildResult()
        show(.working)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Build

    private func buildWorking() {
        layer.addSublayer(ringsLayer)

        mark.backgroundColor = Glass.brandInk
        mark.layer.cornerRadius = 13
        mark.layer.cornerCurve = .continuous
        markLabel.text = "g"
        markLabel.font = .systemFont(ofSize: 27, weight: .bold)
        markLabel.textColor = .white
        markLabel.textAlignment = .center
        mark.addSubview(markLabel)
        markDot.backgroundColor = Glass.accentPrimary
        markDot.layer.cornerRadius = 3.5
        mark.addSubview(markDot)
        addSubview(mark)

        workingTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        workingTitle.textColor = Glass.textPrimary
        workingTitle.textAlignment = .center
        workingTitle.accessibilityIdentifier = "act:skill"
        addSubview(workingTitle)

        intentLabel.font = .systemFont(ofSize: 14, weight: .medium)
        intentLabel.textColor = Glass.textSecondary
        intentLabel.textAlignment = .center
        intentLabel.numberOfLines = 2
        addSubview(intentLabel)

        cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelButton.tintColor = Glass.textPrimary
        cancelButton.backgroundColor = Glass.surfaceCard
        cancelButton.layer.cornerRadius = 18
        cancelButton.layer.borderWidth = Glass.hairlineWidth
        cancelButton.layer.borderColor = Glass.strokeHairline.cgColor
        cancelButton.accessibilityIdentifier = "act:cancel"
        cancelButton.addAction(UIAction { [weak self] _ in self?.delegate?.actClosed() }, for: .touchUpInside)
        addSubview(cancelButton)
    }

    private func buildResult() {
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "act:close"
        closeButton.addAction(UIAction { [weak self] _ in self?.delegate?.actClosed() }, for: .touchUpInside)
        addSubview(closeButton)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Glass.textPrimary
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        textView.isEditable = false
        textView.backgroundColor = Glass.surfaceCard
        textView.layer.cornerRadius = 15
        textView.layer.cornerCurve = .continuous
        textView.layer.borderWidth = Glass.hairlineWidth
        textView.layer.borderColor = Glass.strokeHairline.cgColor
        textView.font = .systemFont(ofSize: 15.5)
        textView.textColor = Glass.textPrimary
        textView.textContainerInset = UIEdgeInsets(top: 11, left: 10, bottom: 11, right: 10)
        textView.accessibilityIdentifier = "act:text"
        addSubview(textView)

        mapView.contentMode = .scaleAspectFill
        mapView.clipsToBounds = true
        mapView.layer.cornerRadius = 15
        mapView.layer.cornerCurve = .continuous
        mapView.backgroundColor = Glass.surfaceCard
        mapView.isUserInteractionEnabled = true
        mapView.isAccessibilityElement = true
        mapView.accessibilityTraits = .button
        mapView.accessibilityLabel = "Map"
        mapView.accessibilityIdentifier = "act:map"
        mapView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(mapTapped)))
        addSubview(mapView)

        table.backgroundColor = Glass.touchableGrid
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.dataSource = self
        table.delegate = self
        table.register(AnswerCell.self, forCellReuseIdentifier: "answer")
        table.register(LinkCell.self, forCellReuseIdentifier: "link")
        table.register(VideoCell.self, forCellReuseIdentifier: "video")
        table.register(PlaceCell.self, forCellReuseIdentifier: "place")
        table.register(OptionCell.self, forCellReuseIdentifier: "option")
        addSubview(table)

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = Glass.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 3
        statusLabel.isUserInteractionEnabled = true
        statusLabel.accessibilityIdentifier = "act:status"
        statusLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retryTapped)))
        addSubview(statusLabel)

        retryButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        style(retryButton, primary: false)
        retryButton.accessibilityIdentifier = "act:retry"
        retryButton.addAction(UIAction { [weak self] _ in self?.retryTapped() }, for: .touchUpInside)
        addSubview(retryButton)

        copyButton.setTitle("Copy", for: .normal)
        style(copyButton, primary: false)
        copyButton.accessibilityIdentifier = "act:copy"
        copyButton.addAction(UIAction { [weak self] _ in
            guard let self, !self.insertText.isEmpty else { return }
            self.delegate?.actCopy(self.insertText)
        }, for: .touchUpInside)
        addSubview(copyButton)

        insertButton.setTitle("Insert", for: .normal)
        insertButton.setImage(UIImage(systemName: "arrow.up",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)),
                              for: .normal)
        insertButton.semanticContentAttribute = .forceRightToLeft
        insertButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 0)
        style(insertButton, primary: true)
        insertButton.accessibilityIdentifier = "act:insert"
        insertButton.addAction(UIAction { [weak self] _ in
            guard let self, !self.insertText.isEmpty else { return }
            self.delegate?.actInsert(self.insertText)
        }, for: .touchUpInside)
        addSubview(insertButton)
    }

    private func style(_ b: UIButton, primary: Bool) {
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.layer.cornerRadius = 19
        b.layer.cornerCurve = .continuous
        if primary {
            b.backgroundColor = Glass.textPrimary
            let ink = Glass.isDark ? Glass.brandInk : UIColor.white
            b.setTitleColor(ink, for: .normal)
            b.tintColor = ink
        } else {
            b.backgroundColor = Glass.surfaceCard
            b.setTitleColor(Glass.textPrimary, for: .normal)
            b.tintColor = Glass.textPrimary
            b.layer.borderWidth = Glass.hairlineWidth
            b.layer.borderColor = Glass.strokeHairline.cgColor
        }
    }

    // MARK: Phases

    /// `keyLetter` puts the held key's letter on the keycap and `title`
    /// names the skill above it; a space-bar act shows the brand g alone.
    func showWorking(intent: String, title: String? = nil, keyLetter: String? = nil) {
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        intentLabel.text = trimmed.isEmpty ? nil
            : "“\(trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed)”"
        markLabel.text = (keyLetter?.isEmpty == false) ? keyLetter!.uppercased() : "g"
        workingTitle.text = title
        show(.working)
    }

    /// A skill's answer arriving token by token: the card fills in place and
    /// the actions appear only once the run has finished.
    func showStreaming(title: String, text: String) {
        if phase != .result || !cards.isEmpty || mapPlace != nil {
            showResult(title: title, cards: [], text: text, insert: "")
        } else {
            textView.text = text
            setNeedsLayout()
        }
        for b in [retryButton, copyButton, insertButton] { b.isHidden = true }
        delegate?.actRetryAvailable(false)
    }

    /// A rewrite's versions as rows: the style on the left, the message on
    /// the right. Tap one to put it in; hold one to copy it.
    func showOptions(_ options: [BackendClient.RewriteOption]) {
        self.options = options
        cards = []
        insertText = ""
        textView.text = ""
        mapPlace = nil
        table.reloadData()
        show(.result)
        setNeedsLayout()
        table.setContentOffset(.zero, animated: false)
    }

    func showResult(title: String, cards: [BackendClient.SearchCard], text: String?, insert: String) {
        titleLabel.text = title
        options = []
        self.cards = cards
        insertText = insert
        textView.text = text ?? ""
        textView.isHidden = (text ?? "").isEmpty
        table.reloadData()
        mapPlace = cards.count == 1 && cards[0].kind == "place"
            && cards[0].lat != nil && cards[0].lon != nil ? cards[0] : nil
        mapView.image = nil
        show(.result)
        if let place = mapPlace, let lat = place.lat, let lon = place.lon {
            loadMap(lat: lat, lon: lon)
        }
    }

    private func loadMap(lat: Double, lon: Double) {
        snapshotter?.cancel()
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate,
                                            latitudinalMeters: 700, longitudinalMeters: 700)
        options.size = CGSize(width: max(bounds.width - 20, 240), height: Self.mapHeight)
        options.traitCollection = UITraitCollection(userInterfaceStyle: Glass.isDark ? .dark : .light)
        let s = MKMapSnapshotter(options: options)
        snapshotter = s
        let started = CACurrentMediaTime()
        s.start { [weak self] snapshot, error in
            guard let self, self.mapPlace != nil else { return }
            guard let snapshot else {
                // No map beats a blank box: fall back to the card alone.
                self.log.error("map snapshot failed: \(String(describing: error), privacy: .public)")
                self.mapPlace = nil
                self.mapView.isHidden = true
                self.setNeedsLayout()
                return
            }
            self.log.log("map snapshot in \(Int((CACurrentMediaTime() - started) * 1000), privacy: .public)ms")
            let pin = UIImage(systemName: "mappin.circle.fill",
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 30))?
                .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
            self.mapView.image = UIGraphicsImageRenderer(size: options.size).image { _ in
                snapshot.image.draw(at: .zero)
                let p = snapshot.point(for: coordinate)
                pin?.draw(in: CGRect(x: p.x - 16, y: p.y - 32, width: 32, height: 32))
            }
        }
    }

    private static let mapHeight: CGFloat = 112

    @objc private func mapTapped() {
        guard let place = mapPlace else { return }
        delegate?.actInsert(place.insertText(style: SettingsStore.current.pasteStyle ?? "titleAndLink"))
    }

    func showFailure(_ message: String) {
        statusLabel.text = message
        show(.failed)
    }

    @objc private func retryTapped() { delegate?.actRetry() }

    private func show(_ p: Phase) {
        phase = p
        let working = p == .working
        let result = p == .result
        for v in [mark, intentLabel, cancelButton] as [UIView] { v.isHidden = !working }
        workingTitle.isHidden = !working || (workingTitle.text ?? "").isEmpty
        ringsLayer.isHidden = !working
        table.isHidden = !result
        // The strip carries ↻ in the website look; glass looks keep their row.
        retryButton.isHidden = !result || Glass.solidLook
        delegate?.actRetryAvailable(!working)
        // Nothing worth putting in the message: no Copy, no Insert.
        for v in [copyButton, insertButton] as [UIView] { v.isHidden = !result || insertText.isEmpty }
        mapView.isHidden = !result || mapPlace == nil
        if !result { snapshotter?.cancel() }
        textView.isHidden = !result || (textView.text ?? "").isEmpty
        titleLabel.isHidden = !result || Glass.solidLook
        closeButton.isHidden = working || Glass.solidLook
        statusLabel.isHidden = p != .failed
        if working { startRings() } else { stopRings() }
        setNeedsLayout()
    }

    // MARK: Rings — quiet neutral strokes; the purple is only the dot.

    private func startRings() {
        stopRings()
        guard !Glass.reduceMotion else { return }
        let now = CACurrentMediaTime()
        for i in 0..<3 {
            let ring = CAShapeLayer()
            ring.fillColor = nil
            ring.strokeColor = Glass.textPrimary.withAlphaComponent(0.16).cgColor
            ring.lineWidth = 1.5
            ringsLayer.addSublayer(ring)

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.35
            scale.toValue = 1.0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 1.8
            group.repeatCount = .infinity
            group.beginTime = now + Double(i) * 0.6
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.fillMode = .backwards
            ring.add(group, forKey: "ring")
        }
        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 1
        breathe.toValue = 0.93
        breathe.duration = 0.9
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        mark.layer.add(breathe, forKey: "breathe")
        setNeedsLayout()
    }

    private func stopRings() {
        ringsLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        mark.layer.removeAnimation(forKey: "breathe")
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height

        // Working: mark centred in the space above the cancel button.
        let markSize: CGFloat = 52
        let centre = CGPoint(x: w / 2, y: (h - 64) / 2)
        mark.bounds = CGRect(x: 0, y: 0, width: markSize, height: markSize)
        mark.center = centre
        markLabel.frame = mark.bounds.offsetBy(dx: 0, dy: -2)
        markDot.frame = CGRect(x: markSize - 13, y: 6, width: 7, height: 7)
        intentLabel.frame = CGRect(x: 24, y: centre.y + markSize / 2 + 12, width: w - 48, height: 40)
        workingTitle.frame = CGRect(x: 24, y: 14, width: w - 48, height: 22)
        cancelButton.frame = CGRect(x: (w - 36) / 2, y: h - 52, width: 36, height: 36)
        ringsLayer.frame = bounds
        let ringDiameter = min(w, h) * 1.1
        for ring in ringsLayer.sublayers ?? [] {
            guard let shape = ring as? CAShapeLayer else { continue }
            shape.bounds = CGRect(x: 0, y: 0, width: ringDiameter, height: ringDiameter)
            shape.position = centre
            shape.path = UIBezierPath(ovalIn: shape.bounds).cgPath
        }

        // Result: header · text · cards · actions. In the website look the
        // strip already names the panel and closes it, so this row collapses.
        let headerH: CGFloat = Glass.solidLook ? 0 : 40
        closeButton.frame = CGRect(x: 6, y: 4, width: 38, height: headerH - 4)
        titleLabel.frame = CGRect(x: 46, y: 4, width: w - 104, height: headerH - 4)
        // Versions to pick from have no Copy/Insert row (a tap inserts, a hold
        // copies), so the list runs to the bottom and ↻ sits in the header.
        let listOnly = !options.isEmpty
        let actionsY = listOnly ? h : h - 52
        retryButton.frame = headerH > 0 && listOnly
            ? CGRect(x: w - 50, y: 4, width: 44, height: headerH - 4)
            : CGRect(x: 10, y: actionsY, width: 44, height: 38)
        let pillsX: CGFloat = Glass.solidLook ? 10 : 62
        let pillsW = w - pillsX - 10
        copyButton.frame = CGRect(x: pillsX, y: actionsY, width: pillsW * 0.38, height: 38)
        insertButton.frame = CGRect(x: pillsX + pillsW * 0.38 + 8, y: actionsY,
                                    width: pillsW * 0.62 - 8, height: 38)
        var y: CGFloat = headerH + 4
        if !mapView.isHidden {
            mapView.frame = CGRect(x: 10, y: y + 2, width: w - 20, height: Self.mapHeight)
            y += Self.mapHeight + 6
        }
        if !textView.isHidden {
            let fit = textView.sizeThatFits(CGSize(width: w - 20, height: .greatestFiniteMagnitude)).height
            let textH = min(max(fit, 48), cards.isEmpty ? actionsY - y - 8 : 120)
            textView.frame = CGRect(x: 10, y: y, width: w - 20, height: textH)
            y += textH + 6
        }
        table.frame = CGRect(x: 0, y: y, width: w, height: max(0, actionsY - y - (listOnly ? 0 : 6)))
        statusLabel.frame = CGRect(x: 24, y: headerH + 4, width: w - 48,
                                   height: max(40, h - headerH - 70))
    }

    // MARK: Cards (the search suite's own cells)

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.isEmpty ? cards.count : options.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if !options.isEmpty {
            return OptionCell.height(for: options[indexPath.row].text, width: tableView.bounds.width)
        }
        switch cards[indexPath.row].kind {
        case "answer": return 104
        case "video": return 82
        case "place": return 78
        default: return 66
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if !options.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "option", for: indexPath) as! OptionCell
            let option = options[indexPath.row]
            cell.fill(option)
            cell.onHold = { [weak self] in self?.delegate?.actCopy(option.text) }
            return cell
        }
        let card = cards[indexPath.row]
        switch card.kind {
        case "answer":
            let cell = tableView.dequeueReusableCell(withIdentifier: "answer", for: indexPath) as! AnswerCell
            cell.fill(card); return cell
        case "video":
            let cell = tableView.dequeueReusableCell(withIdentifier: "video", for: indexPath) as! VideoCell
            cell.fill(card); return cell
        case "place":
            let cell = tableView.dequeueReusableCell(withIdentifier: "place", for: indexPath) as! PlaceCell
            cell.fill(card); return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "link", for: indexPath) as! LinkCell
            cell.fill(card); return cell
        }
    }

    /// Tapping one card drops just that one — a single place out of a list.
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if !options.isEmpty {
            delegate?.actInsert(options[indexPath.row].text)
            return
        }
        let card = cards[indexPath.row]
        if card.kind == "query" {
            if let url = URL(string: card.url) { delegate?.actOpen(url) }
            return
        }
        delegate?.actInsert(card.insertText(style: SettingsStore.current.pasteStyle ?? "titleAndLink"))
    }
}

/// One version of a rewrite: its style, then the message. The website's row.
final class OptionCell: UITableViewCell {
    private let card = UIView()
    private let label = UILabel()
    private let body = UILabel()
    var onHold: (() -> Void)?

    private static let labelW: CGFloat = 92
    private static let bodyFont = UIFont.systemFont(ofSize: 15)

    static func height(for text: String, width: CGFloat) -> CGFloat {
        let textW = width - 20 - 14 - labelW - 12 - 14
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: max(40, textW), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: [.font: bodyFont], context: nil)
        return min(ceil(rect.height), bodyFont.lineHeight * 3) + 24 + 8
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Glass.touchableGrid
        selectionStyle = .none
        card.backgroundColor = Glass.surfaceCard
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        contentView.addSubview(card)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = Glass.textSecondary
        card.addSubview(label)
        body.font = Self.bodyFont
        body.textColor = Glass.textPrimary
        body.numberOfLines = 3
        card.addSubview(body)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.4
        contentView.addGestureRecognizer(hold)
    }

    required init?(coder: NSCoder) { fatalError() }

    func fill(_ option: BackendClient.RewriteOption) {
        label.text = option.label
        body.text = option.text
        accessibilityLabel = "\(option.label): \(option.text)"
        accessibilityIdentifier = "act:option:\(option.id)"
        isAccessibilityElement = true
        accessibilityTraits = .button
        setNeedsLayout()
    }

    @objc private func held(_ g: UILongPressGestureRecognizer) {
        if g.state == .began { onHold?() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = contentView.bounds.inset(by: UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10))
        label.frame = CGRect(x: 14, y: 12, width: Self.labelW, height: 18)
        body.frame = CGRect(x: 14 + Self.labelW + 12, y: 12,
                            width: card.bounds.width - Self.labelW - 40,
                            height: card.bounds.height - 24)
    }
}
