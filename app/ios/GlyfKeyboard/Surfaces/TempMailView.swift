import UIKit

/// The Temp mail panel, inside the g menu's shell: the address with Insert
/// and Copy, how long it is watched for, and what has come in, newest first.
/// A mail opens with its code big and ready to type. The mails themselves
/// live in TempMailWatcher's memory, never on disk.
final class TempMailView: UIView {

    /// Types into the field (the address, a code, a link); the panel closes.
    var onInsert: ((String) -> Void)?
    var onCopy: ((String) -> Void)?
    var onOpenMail: ((String) -> Void)?
    /// Opens a page in the browser (the credit's mail.tm).
    var onOpenLink: ((URL) -> Void)?

    private let watcher = TempMailWatcher.shared
    /// One mail open, rather than the inbox.
    private var detail = false

    // No address yet
    private let createButton = UIButton(type: .system)
    private let createSpinner = UIActivityIndicatorView(style: .medium)
    // The address and its watch
    private let card = UIView()
    private let addressLabel = UILabel()
    private let insertButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private let newButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let watchLabel = UILabel()
    private let watchButton = UIButton(type: .system)
    // The inbox
    private let inbox = ControlScrollView()
    private let emptyLabel = UILabel()
    /// mail.tm asks for a visible link back: one quiet line at the foot.
    private let creditButton = UIButton(type: .system)
    // One mail
    private let mailScroll = ControlScrollView()
    private let subjectLabel = UILabel()
    private let fromLabel = UILabel()
    private let codeCard = UIView()
    private let codeLabel = UILabel()
    private let codeInsert = UIButton(type: .system)
    private let codeCopy = UIButton(type: .system)
    private let linkButton = UIButton(type: .system)
    private let textLabel = UILabel()

    /// The countdown and the "2m"s move on by themselves.
    private var ticker: Timer?
    private var observer: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid

        stylePrimary(createButton, "Create address", id: "tempmail:create")
        createButton.addAction(UIAction { [weak self] _ in self?.create() }, for: .touchUpInside)
        addSubview(createButton)
        createSpinner.color = .white
        createSpinner.hidesWhenStopped = true
        createButton.addSubview(createSpinner)

        card.backgroundColor = Glass.surfaceCard
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        addSubview(card)
        addressLabel.font = .systemFont(ofSize: 15, weight: .medium)
        addressLabel.textColor = Glass.textPrimary
        addressLabel.lineBreakMode = .byTruncatingMiddle
        addressLabel.accessibilityIdentifier = "tempmail:address"
        card.addSubview(addressLabel)
        stylePrimary(insertButton, "Insert", id: "tempmail:insert")
        insertButton.addAction(UIAction { [weak self] _ in
            guard let self, let address = self.watcher.address else { return }
            self.watcher.restartWatch()
            self.onInsert?(address)
        }, for: .touchUpInside)
        card.addSubview(insertButton)
        styleSecondary(copyButton, "Copy", id: "tempmail:copy")
        copyButton.addAction(UIAction { [weak self] _ in
            guard let self, let address = self.watcher.address else { return }
            self.onCopy?(address)
        }, for: .touchUpInside)
        card.addSubview(copyButton)
        styleSmall(newButton, "New", id: "tempmail:new")
        newButton.addAction(UIAction { [weak self] _ in self?.create() }, for: .touchUpInside)
        card.addSubview(newButton)
        styleSmall(deleteButton, "Delete", id: "tempmail:delete")
        deleteButton.addAction(UIAction { [weak self] _ in self?.watcher.delete() }, for: .touchUpInside)
        card.addSubview(deleteButton)
        watchLabel.font = .systemFont(ofSize: 12)
        watchLabel.textColor = Glass.textSecondary
        watchLabel.accessibilityIdentifier = "tempmail:watching"
        addSubview(watchLabel)
        watchButton.setTitle("Watch again", for: .normal)
        watchButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        watchButton.setTitleColor(Glass.chipAccent, for: .normal)
        watchButton.accessibilityIdentifier = "tempmail:watch"
        watchButton.addAction(UIAction { [weak self] _ in self?.watcher.restartWatch() }, for: .touchUpInside)
        addSubview(watchButton)

        inbox.alwaysBounceVertical = true
        inbox.showsVerticalScrollIndicator = false
        addSubview(inbox)
        emptyLabel.text = "No mail yet"
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = Glass.textSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.accessibilityIdentifier = "tempmail:empty"
        addSubview(emptyLabel)
        creditButton.setTitle("via mail.tm", for: .normal)
        creditButton.titleLabel?.font = .systemFont(ofSize: 11)
        creditButton.setTitleColor(Glass.textSecondary, for: .normal)
        creditButton.accessibilityIdentifier = "tempmail:credit"
        creditButton.addAction(UIAction { [weak self] _ in
            guard let url = URL(string: "https://mail.tm") else { return }
            self?.onOpenLink?(url)
        }, for: .touchUpInside)
        addSubview(creditButton)

        mailScroll.alwaysBounceVertical = true
        mailScroll.showsVerticalScrollIndicator = false
        addSubview(mailScroll)
        subjectLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        subjectLabel.textColor = Glass.textPrimary
        subjectLabel.numberOfLines = 3
        subjectLabel.accessibilityIdentifier = "tempmail:subject"
        fromLabel.font = .systemFont(ofSize: 12)
        fromLabel.textColor = Glass.textSecondary
        fromLabel.accessibilityIdentifier = "tempmail:from"
        codeCard.backgroundColor = Glass.surfaceCard
        codeCard.layer.cornerRadius = 12
        codeCard.layer.cornerCurve = .continuous
        codeLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        codeLabel.textColor = Glass.textPrimary
        codeLabel.adjustsFontSizeToFitWidth = true
        codeLabel.minimumScaleFactor = 0.6
        codeLabel.accessibilityIdentifier = "tempmail:code"
        stylePrimary(codeInsert, "Insert", id: "tempmail:code:insert")
        codeInsert.addAction(UIAction { [weak self] _ in
            guard let code = self?.watcher.openedMail?.code else { return }
            self?.onInsert?(code)
        }, for: .touchUpInside)
        styleSecondary(codeCopy, "Copy", id: "tempmail:code:copy")
        codeCopy.addAction(UIAction { [weak self] _ in
            guard let code = self?.watcher.openedMail?.code else { return }
            self?.onCopy?(code)
        }, for: .touchUpInside)
        styleSecondary(linkButton, "Insert link", id: "tempmail:link")
        linkButton.addAction(UIAction { [weak self] _ in
            guard let link = self?.watcher.openedMail?.link else { return }
            self?.onInsert?(link)
        }, for: .touchUpInside)
        textLabel.font = .systemFont(ofSize: 14)
        textLabel.textColor = Glass.textPrimary
        textLabel.numberOfLines = 0
        textLabel.accessibilityIdentifier = "tempmail:text"
        for v in [subjectLabel, fromLabel, codeCard, codeLabel, codeInsert, codeCopy, linkButton, textLabel] as [UIView] {
            mailScroll.addSubview(v)
        }

        observer = NotificationCenter.default.addObserver(
            forName: TempMailWatcher.changed, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        ticker?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Look

    private func stylePrimary(_ b: UIButton, _ title: String, id: String) {
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = Glass.accentPrimary
        b.layer.cornerCurve = .continuous
        b.accessibilityIdentifier = id
    }

    private func styleSecondary(_ b: UIButton, _ title: String, id: String) {
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.setTitleColor(Glass.textPrimary, for: .normal)
        b.backgroundColor = Glass.fillField
        b.layer.cornerCurve = .continuous
        b.accessibilityIdentifier = id
    }

    private func styleSmall(_ b: UIButton, _ title: String, id: String) {
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        b.setTitleColor(Glass.textSecondary, for: .normal)
        b.accessibilityIdentifier = id
    }

    // MARK: Showing

    /// The inbox, or the open mail.
    func show(detail: Bool) {
        self.detail = detail
        refresh()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
    }

    private func create() {
        createSpinner.startAnimating()
        createButton.setTitle("", for: .normal)
        watcher.create { [weak self] _ in self?.refresh() }
    }

    /// The seconds on the watch, and how long ago each mail came.
    private func tick() {
        guard !isHidden, !watcher.endIfExpired(), watcher.address != nil else { return }
        if !mailScroll.isHidden {
            if let mail = watcher.openedMail { fromLabel.text = fromLine(mail) }
            return
        }
        renderWatch()
        for case let row as UIControl in inbox.subviews {
            let i = row.tag - 3000
            guard watcher.messages.indices.contains(i) else { continue }
            (row.viewWithTag(3) as? UILabel)?.text = TempMailRules.ago(watcher.messages[i].receivedAt)
        }
    }

    private func renderWatch() {
        if watcher.isWatching {
            watchLabel.text = "Watching · \(TempMailRules.left(watcher.watchLeft)) left"
            watchButton.isHidden = true
        } else {
            watchLabel.text = "Stopped ·"
            watchButton.isHidden = false
        }
        setNeedsLayout()
    }

    func refresh() {
        let address = watcher.address
        let hasAddress = address != nil
        if !watcher.busy {
            createSpinner.stopAnimating()
            createButton.setTitle("Create address", for: .normal)
        }
        newButton.isEnabled = !watcher.busy
        createButton.isHidden = hasAddress
        let showDetail = hasAddress && detail && watcher.openedMail != nil
        let showInbox = hasAddress && !showDetail
        for v in [card, watchLabel, inbox] as [UIView] { v.isHidden = !showInbox }
        watchButton.isHidden = true
        emptyLabel.isHidden = !showInbox || !watcher.messages.isEmpty
        mailScroll.isHidden = !showDetail
        addressLabel.text = address
        addressLabel.accessibilityLabel = address
        if showInbox {
            renderWatch()
            buildRows()
        }
        if showDetail, let mail = watcher.openedMail { fill(mail) }
        setNeedsLayout()
    }

    // MARK: The inbox

    private func buildRows() {
        inbox.subviews.forEach { $0.removeFromSuperview() }
        for (i, mail) in watcher.messages.enumerated() {
            // A container, so the code's own Insert is a control of its own.
            let row = UIControl()
            row.tag = 3000 + i
            row.backgroundColor = Glass.surfaceCard
            row.layer.cornerRadius = 12
            row.layer.cornerCurve = .continuous
            row.accessibilityIdentifier = "tempmail:row:\(i)"
            let sender = UILabel()
            sender.tag = 1
            sender.text = self.sender(mail)
            sender.font = .systemFont(ofSize: 14, weight: .bold)
            sender.textColor = Glass.textPrimary
            let subject = UILabel()
            subject.tag = 2
            subject.text = mail.subject
            subject.font = .systemFont(ofSize: 13)
            subject.textColor = Glass.textSecondary
            let time = UILabel()
            time.tag = 3
            time.text = TempMailRules.ago(mail.receivedAt)
            time.font = .systemFont(ofSize: 12)
            time.textColor = Glass.textSecondary
            time.textAlignment = .right
            for label in [sender, subject, time] {
                label.isUserInteractionEnabled = false
                row.addSubview(label)
            }
            if let code = mail.code {
                // The code, and its Insert, without opening the mail.
                let pill = UIControl()
                pill.tag = 4
                pill.backgroundColor = Glass.fillField
                pill.layer.cornerCurve = .continuous
                pill.accessibilityIdentifier = "tempmail:rowcode:\(i)"
                pill.accessibilityLabel = "\(code), Insert"
                pill.isAccessibilityElement = true
                pill.accessibilityTraits = .button
                // Tags apart from the row's own: a tag lookup searches down.
                let digits = UILabel()
                digits.tag = 11
                digits.text = code
                digits.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
                digits.textColor = Glass.textPrimary
                let verb = UILabel()
                verb.tag = 12
                verb.text = "Insert"
                verb.font = .systemFont(ofSize: 13, weight: .semibold)
                verb.textColor = Glass.chipAccent
                for label in [digits, verb] {
                    label.isUserInteractionEnabled = false
                    pill.addSubview(label)
                }
                pill.addAction(UIAction { [weak self] _ in self?.onInsert?(code) }, for: .touchUpInside)
                row.addSubview(pill)
            }
            let id = mail.id
            row.addAction(UIAction { [weak self] _ in self?.onOpenMail?(id) }, for: .touchUpInside)
            inbox.addSubview(row)
        }
    }

    // MARK: One mail

    private func fill(_ mail: TempMailMessage) {
        subjectLabel.text = mail.subject.isEmpty ? sender(mail) : mail.subject
        fromLabel.text = fromLine(mail)
        // Spaced a little, so six digits read off at a glance.
        codeLabel.attributedText = mail.code.map { NSAttributedString(string: $0, attributes: [.kern: 2]) }
        codeLabel.accessibilityLabel = mail.code
        for v in [codeCard, codeLabel, codeInsert, codeCopy] as [UIView] { v.isHidden = mail.code == nil }
        linkButton.isHidden = mail.link == nil
        textLabel.text = mail.text
    }

    private func sender(_ mail: TempMailMessage) -> String {
        mail.from.isEmpty ? mail.fromAddress : mail.from
    }

    /// "Acme · 2m".
    private func fromLine(_ mail: TempMailMessage) -> String {
        "\(sender(mail)) · \(TempMailRules.ago(mail.receivedAt))"
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, side: CGFloat = 12
        // The credit sits under everything, on every screen of the panel.
        let creditH: CGFloat = 20
        creditButton.frame = CGRect(x: (w - 120) / 2, y: bounds.height - creditH, width: 120, height: creditH)
        let h = bounds.height - creditH

        createButton.frame = CGRect(x: (w - 200) / 2, y: (h - 44) / 2, width: 200, height: 44)
        createButton.layer.cornerRadius = 22
        createSpinner.center = CGPoint(x: 100, y: 22)

        // The address on a line of its own, whole where it fits: Insert and
        // Copy under it, New and Delete at the far end (as on Android).
        card.frame = CGRect(x: side, y: 8, width: w - side * 2, height: 82)
        let cw = card.bounds.width
        addressLabel.frame = CGRect(x: 14, y: 10, width: cw - 28, height: 22)
        let insertW = max(84, ceil(insertButton.intrinsicContentSize.width) + 32)
        insertButton.frame = CGRect(x: 10, y: 40, width: insertW, height: 32)
        insertButton.layer.cornerRadius = 16
        let copyW = max(72, ceil(copyButton.intrinsicContentSize.width) + 28)
        copyButton.frame = CGRect(x: insertButton.frame.maxX + 8, y: 40, width: copyW, height: 32)
        copyButton.layer.cornerRadius = 16
        let deleteW = ceil(deleteButton.intrinsicContentSize.width) + 16
        deleteButton.frame = CGRect(x: cw - 4 - deleteW, y: 40, width: deleteW, height: 32)
        let newW = ceil(newButton.intrinsicContentSize.width) + 16
        newButton.frame = CGRect(x: deleteButton.frame.minX - newW, y: 40, width: newW, height: 32)

        // "Watching · 14:32 left", or "Stopped ·" with Watch again after it.
        let lineY = card.frame.maxY + 6
        let labelW = ceil(watchLabel.sizeThatFits(CGSize(width: w, height: 22)).width)
        watchLabel.frame = CGRect(x: side + 4, y: lineY, width: min(labelW, w - side * 2 - 8), height: 22)
        let watchW = watchButton.isHidden ? 0 : ceil(watchButton.intrinsicContentSize.width)
        watchButton.frame = CGRect(x: watchLabel.frame.maxX + 4, y: lineY - 3, width: watchW, height: 28)

        // What came in, newest first.
        let inboxY = lineY + 26
        inbox.frame = CGRect(x: 0, y: inboxY, width: w, height: max(0, h - inboxY))
        emptyLabel.frame = inbox.frame
        let rowH: CGFloat = 52, gap: CGFloat = 6, rw = w - side * 2
        var y: CGFloat = 0
        for case let row as UIControl in inbox.subviews {
            row.frame = CGRect(x: side, y: y, width: rw, height: rowH)
            let timeW: CGFloat = 40
            row.viewWithTag(3)?.frame = CGRect(x: rw - 12 - timeW, y: 8, width: timeW, height: 18)
            row.viewWithTag(1)?.frame = CGRect(x: 12, y: 8, width: rw - 24 - timeW - 8, height: 18)
            var subjectRight = rw - 12
            if let pill = row.viewWithTag(4) {
                let digits = pill.viewWithTag(11) as? UILabel
                let verb = pill.viewWithTag(12) as? UILabel
                let dw = ceil(digits?.intrinsicContentSize.width ?? 0)
                let vw = ceil(verb?.intrinsicContentSize.width ?? 0)
                let pw = 10 + dw + 8 + vw + 10
                pill.frame = CGRect(x: rw - 8 - pw, y: 26, width: pw, height: 22)
                pill.layer.cornerRadius = 11
                digits?.frame = CGRect(x: 10, y: 0, width: dw, height: 22)
                verb?.frame = CGRect(x: 10 + dw + 8, y: 0, width: vw, height: 22)
                subjectRight = pill.frame.minX - 8
            }
            row.viewWithTag(2)?.frame = CGRect(x: 12, y: 28, width: max(0, subjectRight - 12), height: 17)
            y += rowH + gap
        }
        inbox.contentSize = CGSize(width: w, height: max(0, y - gap) + 8)

        // One mail: its subject and sender, the code big with Insert and Copy,
        // the link, then the words, all of it scrolling.
        mailScroll.frame = CGRect(x: 0, y: 0, width: w, height: h)
        let mw = w - side * 2
        let subjectH = ceil(subjectLabel.sizeThatFits(CGSize(width: mw, height: .greatestFiniteMagnitude)).height)
        subjectLabel.frame = CGRect(x: side, y: 10, width: mw, height: subjectH)
        fromLabel.frame = CGRect(x: side, y: subjectLabel.frame.maxY + 2, width: mw, height: 16)
        var my = fromLabel.frame.maxY + 10
        if !codeLabel.isHidden {
            // The code on a card of its own, Copy and Insert at its end.
            codeCard.frame = CGRect(x: side, y: my, width: mw, height: 56)
            let iw = ceil(codeInsert.intrinsicContentSize.width) + 28
            let cpw = ceil(codeCopy.intrinsicContentSize.width) + 24
            codeInsert.frame = CGRect(x: codeCard.frame.maxX - 10 - iw, y: my + 11, width: iw, height: 34)
            codeInsert.layer.cornerRadius = 17
            codeCopy.frame = CGRect(x: codeInsert.frame.minX - 8 - cpw, y: my + 11, width: cpw, height: 34)
            codeCopy.layer.cornerRadius = 17
            codeLabel.frame = CGRect(x: side + 14, y: my + 6, width: max(0, codeCopy.frame.minX - side - 24), height: 44)
            my += 64
        }
        if !linkButton.isHidden {
            let lw = ceil(linkButton.intrinsicContentSize.width) + 28
            linkButton.frame = CGRect(x: side, y: my, width: lw, height: 32)
            linkButton.layer.cornerRadius = 16
            my += 40
        }
        let textH = ceil(textLabel.sizeThatFits(CGSize(width: mw, height: .greatestFiniteMagnitude)).height)
        textLabel.frame = CGRect(x: side, y: my, width: mw, height: textH)
        mailScroll.contentSize = CGSize(width: w, height: textLabel.frame.maxY + 12)
    }
}
