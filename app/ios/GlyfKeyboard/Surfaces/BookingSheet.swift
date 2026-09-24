import UIKit

/// Book a time: the day's open times on a Cal.com page, as pills. Tapping one
/// asks who it is for, one line with a name, an email and any guests' emails
/// ("Sam Lee sam@x.com ria@y.com"), then books it through Cal.com, which
/// emails everyone the invite, the way booking on Cal.com's own page does.
/// "Send the link" puts the page, or the time on it, in the message instead.
/// Calendly shares times only with the host's own sign-in, so it offers the
/// page on that day.
///
/// `mine` is the person's own page (from the app): the who is the other
/// person. Someone else's page (a link in the chat) starts from the person's
/// own name and email in the vault.
final class BookingSheet: UIView {

    var onBack: (() -> Void)?
    var onInsert: ((String) -> Void)?
    /// The who is being typed: the keys should come up and feed `whoEditor`.
    var onEditWho: ((InlineEditor) -> Void)?
    /// Typing ended, or the shape changed.
    var onLayoutChange: (() -> Void)?

    /// Height of the strip over the keys while the who is typed.
    static let editStripHeight: CGFloat = 92

    private let link: String
    private let mine: Bool
    private var day: Date
    private let cal = Calendar.current
    private var pageURL: String?
    private var request = 0
    private var calcom = false

    /// The time chosen, and its page.
    private var picked: (start: Date, url: String)?
    private var who: String
    private(set) var editingWho = false
    let whoEditor = InlineEditor(placeholder: "Name and email, then guests")

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let dayLabel = UILabel()
    private let prevButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let scroll = UIScrollView()
    private var pills: [UIButton] = []
    private let status = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let linkButton = UIButton(type: .system)
    private let bookButton = UIButton(type: .system)
    private let whoCard = UIControl()
    private let whoLabel = UILabel()
    private let whoValue = UILabel()
    private let note = UILabel()
    private let stripCancel = UIButton(type: .system)
    private let stripDone = UIButton(type: .system)
    private let stripHint = UILabel()

    init(link: String, day: Date, mine: Bool, me: String = "") {
        self.link = link
        self.mine = mine
        self.day = Calendar.current.startOfDay(for: day)
        self.who = mine ? "" : me
        super.init(frame: .zero)
        build()
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        backButton.setImage(UIImage(systemName: "chevron.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        backButton.tintColor = Glass.textPrimary
        backButton.accessibilityIdentifier = "booking:back"
        backButton.accessibilityLabel = "Back"
        backButton.addAction(UIAction { [weak self] _ in self?.back() }, for: .touchUpInside)
        addSubview(backButton)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Glass.textPrimary
        addSubview(titleLabel)
        dayLabel.font = .systemFont(ofSize: 13)
        dayLabel.textColor = Glass.textSecondary
        dayLabel.textAlignment = .right
        addSubview(dayLabel)

        for (b, symbol, id, step) in [(prevButton, "chevron.left", "booking:prev", -1),
                                      (nextButton, "chevron.right", "booking:next", 1)] {
            b.setImage(UIImage(systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)), for: .normal)
            b.tintColor = Glass.textPrimary
            b.accessibilityIdentifier = id
            b.addAction(UIAction { [weak self] _ in self?.step(step) }, for: .touchUpInside)
            addSubview(b)
        }

        scroll.showsVerticalScrollIndicator = false
        addSubview(scroll)

        status.font = .systemFont(ofSize: 14)
        status.textColor = Glass.textSecondary
        status.textAlignment = .center
        status.numberOfLines = 2
        status.accessibilityIdentifier = "booking:status"
        addSubview(status)
        spinner.hidesWhenStopped = true
        addSubview(spinner)

        // Who: one row, as Calendar's own rows look.
        whoCard.backgroundColor = Glass.surfaceCard
        whoCard.layer.cornerRadius = 12
        whoCard.layer.cornerCurve = .continuous
        whoCard.accessibilityIdentifier = "booking:who"
        whoCard.isAccessibilityElement = true
        whoCard.accessibilityTraits = .button
        whoCard.addAction(UIAction { [weak self] _ in self?.beginWho() }, for: .touchUpInside)
        whoLabel.text = mine ? "For" : "You"
        whoLabel.font = .systemFont(ofSize: 16)
        whoLabel.textColor = Glass.textPrimary
        whoValue.font = .systemFont(ofSize: 15)
        whoValue.textAlignment = .right
        whoValue.lineBreakMode = .byTruncatingHead
        for v in [whoLabel, whoValue] {
            v.isUserInteractionEnabled = false
            whoCard.addSubview(v)
        }
        addSubview(whoCard)

        note.font = .systemFont(ofSize: 13)
        note.textColor = Glass.textSecondary
        note.numberOfLines = 2
        note.accessibilityIdentifier = "booking:note"
        addSubview(note)

        for (b, title, id, filled) in [(linkButton, "Send my link", "booking:link", false),
                                       (bookButton, "Book it", "booking:book", true)] {
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            b.setTitleColor(filled ? .white : Glass.textPrimary, for: .normal)
            b.backgroundColor = filled ? Glass.accentPrimary : Glass.surfaceCard
            b.layer.cornerCurve = .continuous
            b.accessibilityIdentifier = id
            addSubview(b)
        }
        linkButton.addAction(UIAction { [weak self] _ in self?.sendLink() }, for: .touchUpInside)
        bookButton.addAction(UIAction { [weak self] _ in self?.book() }, for: .touchUpInside)

        stripCancel.setTitle("Cancel", for: .normal)
        stripCancel.titleLabel?.font = .systemFont(ofSize: 16)
        stripCancel.tintColor = Glass.accentPrimary
        stripCancel.addAction(UIAction { [weak self] _ in self?.endWho(keep: false) }, for: .touchUpInside)
        stripDone.setTitle("Done", for: .normal)
        stripDone.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        stripDone.tintColor = Glass.accentPrimary
        stripDone.accessibilityIdentifier = "booking:who:done"
        stripDone.addAction(UIAction { [weak self] _ in self?.endWho() }, for: .touchUpInside)
        whoEditor.accessibilityIdentifier = "booking:who:field"
        whoEditor.showsEnd = true
        whoEditor.onChange = { [weak self] text in self?.whoChanged(text) }
        stripHint.font = .systemFont(ofSize: 13)
        stripHint.textColor = Glass.textSecondary
        stripHint.accessibilityIdentifier = "booking:who:hint"
        for v in [stripCancel, stripDone, whoEditor, stripHint] as [UIView] {
            v.isHidden = true
            addSubview(v)
        }
        render()
    }

    // MARK: behaviour

    private func back() {
        if picked != nil {
            picked = nil
            note.text = nil
            render()
            return
        }
        onBack?()
    }

    private func step(_ n: Int) {
        guard let d = cal.date(byAdding: .day, value: n, to: day) else { return }
        // Nothing to book in the past.
        guard d >= cal.startOfDay(for: Date()) else { return }
        day = d
        load()
    }

    private static func iso(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: day)
    }

    private func load() {
        picked = nil
        pills.forEach { $0.removeFromSuperview() }
        pills = []
        status.text = nil
        spinner.startAnimating()
        request += 1
        let mine = request
        render()
        BackendClient.shared.bookingSlots(link: link, date: Self.iso(day)) { [weak self] result, error in
            guard let self, mine == self.request else { return }
            self.spinner.stopAnimating()
            guard let result else {
                self.status.text = error ?? "Couldn't reach the booking page"
                return
            }
            self.pageURL = result.bookingUrl
            self.calcom = result.provider == "calcom"
            if !self.calcom {
                self.status.text = "Calendly shows times only on its own page. Send the link for this day."
                return
            }
            let slots = result.days.first(where: { $0.date == Self.iso(self.day) })?.slots ?? []
            let now = Date()
            let open = slots.filter { $0.start > now }
            if open.isEmpty { self.status.text = "Nothing open this day" }
            for (i, slot) in open.enumerated() {
                let b = UIButton(type: .custom)
                b.setTitle(CalendarText.clock(slot.start), for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
                b.setTitleColor(Glass.textPrimary, for: .normal)
                b.backgroundColor = Glass.surfaceCard
                b.layer.cornerRadius = 10
                b.layer.cornerCurve = .continuous
                b.accessibilityIdentifier = "booking:slot:\(i)"
                b.accessibilityLabel = CalendarText.clock(slot.start)
                b.addAction(UIAction { [weak self] _ in self?.pick(slot.start, url: slot.url) }, for: .touchUpInside)
                self.scroll.addSubview(b)
                self.pills.append(b)
            }
            self.render()
        }
    }

    private func pick(_ start: Date, url: String) {
        picked = (start, url)
        note.text = "Cal.com emails the invite to everyone."
        render()
        // Nobody to book for yet: straight to typing who.
        if EventParse.people(who).emails.isEmpty { beginWho() }
    }

    private func beginWho() {
        guard !editingWho else { return }
        editingWho = true
        whoEditor.setText(who)
        whoEditor.isActive = true
        onEditWho?(whoEditor)
        render()
        onLayoutChange?()
    }

    /// Return on the keys, or Done. Cancel puts the line back as it was.
    func endWho(keep: Bool = true) {
        guard editingWho else { return }
        if keep { who = whoEditor.text.trimmingCharacters(in: .whitespaces) }
        editingWho = false
        whoEditor.isActive = false
        render()
        onLayoutChange?()
    }

    private func whoChanged(_ text: String) {
        stripHint.text = Self.summary(text) ?? (mine ? "Their name and email, then any guests"
                                                     : "Your name and email, then any guests")
    }

    /// "Sam Lee · sam@x.com · 1 guest".
    private static func summary(_ line: String) -> String? {
        let p = EventParse.people(line)
        guard let first = p.emails.first else { return p.name.isEmpty ? nil : "\(p.name) · add an email" }
        var parts = [p.name, first].filter { !$0.isEmpty }
        let guests = p.emails.count - 1
        if guests > 0 { parts.append(guests == 1 ? "1 guest" : "\(guests) guests") }
        return parts.joined(separator: " · ")
    }

    private func sendLink() {
        if let picked {
            onInsert?("How about \(CalendarText.dayLabel(picked.start)) at \(CalendarText.clock(picked.start))? Book it here: \(picked.url)")
            return
        }
        let page = pageURL ?? (link.hasPrefix("http") ? link : "https://\(link)")
        onInsert?("Pick a time that works for you: \(page)")
    }

    private func book() {
        guard let picked else { return }
        if editingWho { endWho() }
        let p = EventParse.people(who)
        guard let email = p.emails.first else {
            note.text = mine ? "Add their email to book it." : "Add your email to book it."
            beginWho()
            return
        }
        let name = p.name.isEmpty ? String(email.split(separator: "@").first ?? "") : p.name
        bookButton.isEnabled = false
        bookButton.setTitle("Booking…", for: .normal)
        BackendClient.shared.bookSlot(link: link, start: picked.start, name: name, email: email,
                                      guests: Array(p.emails.dropFirst())) { [weak self] booked, error in
            guard let self else { return }
            self.bookButton.isEnabled = true
            self.bookButton.setTitle("Book it", for: .normal)
            guard let booked else {
                self.note.text = error ?? "Couldn't book it. Try again"
                return
            }
            let when = "\(CalendarText.dayLabel(booked.start ?? picked.start)), \(CalendarText.clock(booked.start ?? picked.start))"
            let people = booked.invited.isEmpty ? p.emails : booked.invited
            let list = people.count > 1 ? people.dropLast().joined(separator: ", ") + " and " + people.last! : (people.first ?? email)
            var line = "Booked for \(when). The invite is on its way to \(list)."
            if let call = booked.meetingUrl, call.hasPrefix("http") { line += " Call: \(call)" }
            self.onInsert?(line)
        }
    }

    // MARK: render

    private func render() {
        let confirming = picked != nil
        let strip = editingWho
        titleLabel.text = confirming ? "\(CalendarText.dayLabel(picked!.start)) · \(CalendarText.clock(picked!.start))"
                                     : "Book a time"
        dayLabel.text = CalendarText.dayLabel(day)
        prevButton.isEnabled = day > cal.startOfDay(for: Date())
        prevButton.alpha = prevButton.isEnabled ? 1 : 0.3
        for v in [dayLabel, prevButton, nextButton, scroll] as [UIView] { v.isHidden = confirming || strip }
        status.isHidden = confirming || strip || status.text == nil
        for v in [whoCard, note] as [UIView] { v.isHidden = !confirming || strip }
        bookButton.isHidden = !confirming || strip
        linkButton.isHidden = strip
        linkButton.setTitle(confirming ? "Send the link" : "Send my link", for: .normal)
        for v in [backButton, titleLabel] as [UIView] { v.isHidden = strip }
        for v in [stripCancel, stripDone, whoEditor, stripHint] as [UIView] { v.isHidden = !strip }
        if strip { whoChanged(whoEditor.text) }

        let summary = Self.summary(who)
        whoValue.text = summary ?? (mine ? "Their name and email" : "Your name and email")
        whoValue.textColor = summary == nil ? Glass.textSecondary : Glass.textPrimary
        whoCard.accessibilityLabel = "\(whoLabel.text ?? ""), \(whoValue.text ?? "")"
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let pad: CGFloat = 12

        if editingWho {
            let rowH: CGFloat = 38
            stripCancel.frame = CGRect(x: 4, y: 8, width: 66, height: rowH)
            stripDone.frame = CGRect(x: w - 62, y: 8, width: 58, height: rowH)
            whoEditor.frame = CGRect(x: stripCancel.frame.maxX + 2, y: 8,
                                     width: stripDone.frame.minX - stripCancel.frame.maxX - 6, height: rowH)
            stripHint.frame = CGRect(x: whoEditor.frame.minX + 4, y: whoEditor.frame.maxY + 6,
                                     width: whoEditor.frame.width, height: 18)
            return
        }

        let headerH: CGFloat = 34
        backButton.frame = CGRect(x: 4, y: 2, width: 32, height: 30)
        nextButton.frame = CGRect(x: w - pad - 28, y: 2, width: 28, height: 30)
        prevButton.frame = CGRect(x: nextButton.frame.minX - 28, y: 2, width: 28, height: 30)
        dayLabel.frame = CGRect(x: prevButton.frame.minX - 110, y: 2, width: 106, height: 30)
        let titleRight = picked != nil ? w - pad : dayLabel.frame.minX - 6
        titleLabel.frame = CGRect(x: backButton.frame.maxX + 2, y: 2, width: titleRight - backButton.frame.maxX - 2, height: 30)

        let actionH: CGFloat = 38
        let actionY = bounds.height - actionH - 8
        if picked != nil {
            let half = ((w - pad * 2 - 8) / 2).rounded(.down)
            linkButton.frame = CGRect(x: pad, y: actionY, width: half, height: actionH)
            bookButton.frame = CGRect(x: pad + half + 8, y: actionY, width: w - pad * 2 - half - 8, height: actionH)
            whoCard.frame = CGRect(x: pad, y: headerH + 6, width: w - pad * 2, height: 44)
            whoLabel.frame = CGRect(x: 14, y: 0, width: 50, height: 44)
            whoValue.frame = CGRect(x: 66, y: 0, width: whoCard.bounds.width - 80, height: 44)
            note.frame = CGRect(x: pad + 4, y: whoCard.frame.maxY + 6, width: w - pad * 2 - 8, height: 36)
        } else {
            linkButton.frame = CGRect(x: pad, y: actionY, width: w - pad * 2, height: actionH)
        }
        for b in [linkButton, bookButton] { b.layer.cornerRadius = actionH / 2 }

        scroll.frame = CGRect(x: pad, y: headerH + 4, width: w - pad * 2, height: max(0, actionY - headerH - 12))
        status.frame = CGRect(x: pad, y: scroll.frame.minY, width: scroll.frame.width, height: min(scroll.frame.height, 52))
        spinner.center = CGPoint(x: w / 2, y: scroll.frame.midY)

        // Four times to a row, Calendar's time pills.
        let cols: CGFloat = 4
        let gap: CGFloat = 8
        let pw = (scroll.frame.width - gap * (cols - 1)) / cols
        let ph: CGFloat = 36
        for (i, b) in pills.enumerated() {
            let r = CGFloat(i / Int(cols)), c = CGFloat(i % Int(cols))
            b.frame = CGRect(x: c * (pw + gap), y: r * (ph + gap), width: pw, height: ph)
        }
        let rows = ceil(CGFloat(pills.count) / cols)
        scroll.contentSize = CGSize(width: scroll.frame.width, height: max(0, rows * (ph + gap) - gap))
    }
}
