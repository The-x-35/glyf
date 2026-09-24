import UIKit

/// The keyboard's calendar: the day's events, full width, because that is
/// what you reach for mid-message. Tap one to put it in the message, or share
/// when you are free that day. Month opens the grid to jump to another day.
/// Events come straight from the phone's calendar when the keyboard may read
/// it (Full Access, and the app allowed), else from the app's copy
/// (calendar.json); without either it is still a calendar, and offers to
/// connect. + opens New Event (EventComposer).
final class CalendarSurface: UIView {

    weak var delegate: ConnectorSurfaceDelegate?

    private let cal = Calendar.current
    private let hasFullAccess: Bool
    private var events: [CalendarText.Event] = []
    private var connected = false
    /// Read from EventKit itself rather than the app's copy.
    private var live = false
    private var composer: EventComposer?
    private var booking: BookingSheet?
    /** The person's Cal.com or Calendly page, set in the app. */
    private var bookingLink: String? {
        let link = SettingsStore.current.bookingLink?.trimmingCharacters(in: .whitespaces) ?? ""
        return link.isEmpty ? nil : link
    }
    /// The event just added, drawn out for a moment in the day's list.
    private var justAdded: CalendarText.Event?
    /// Its row, scrolled into view once laid out, the way Calendar shows a new event.
    private weak var justAddedRow: UIView?
    /// The lit row, so the light can go out without rebuilding the list.
    private weak var litRow: UIView?
    /// Add was tapped and the call link is on its way: once is enough.
    private var adding = false
    private var month: Date
    private var selected: Date

    /// The grid is a detour for picking another day; the events are the point.
    private var showingMonth = false

    private let titleLabel = UILabel()
    private let prevButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private let newButton = UIButton(type: .system)
    private let callButton = UIButton(type: .system)
    private let bookButton = UIButton(type: .system)
    private var weekdayLabels: [UILabel] = []
    private var dayButtons: [UIButton] = []
    /// The event dot under each day (kept apart from the buttons' tags).
    private var dayDots: [UIView] = []

    private let agenda = UIScrollView()
    private let agendaStack = UIStackView()
    private let freeButton = UIButton(type: .system)
    private let connectButton = UIButton(type: .system)
    private let dateButton = UIButton(type: .system)

    init(hasFullAccess: Bool = false) {
        let today = Calendar.current.startOfDay(for: Date())
        month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
        selected = today
        self.hasFullAccess = hasFullAccess
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid
        load()
        build()
        render()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func load() {
        if CalendarWriter.access(hasFullAccess: hasFullAccess) == .ready, CalendarWriter.canRead {
            live = true
            connected = true
            let from = cal.date(byAdding: .day, value: -7, to: month) ?? month
            let to = cal.date(byAdding: .day, value: 45, to: month) ?? month
            events = CalendarWriter.events(from: from, to: to)
            return
        }
        let json = AppGroupStore.readJSON(name: "calendar.json")
        connected = json != nil
        events = CalendarText.events(fromJSON: json)
    }

    /// While a title or a who is typed the panel is a strip over the keys.
    var editingTitle: Bool { composer?.editingTitle == true || booking?.editingWho == true }
    var composing: Bool { composer != nil }

    /// Return on the keys: the title (or the who) is done.
    func returnPressed() {
        composer?.endTitle()
        booking?.endWho()
    }

    /// New Event, filled from a plan when there is one ("dinner friday 8pm"),
    /// else the chosen day at the next hour (9 AM on another day).
    func compose(plan: EventParse.Plan? = nil) {
        let draft: EventComposer.Draft
        if let plan {
            // The plan is in the message already: nothing more goes in.
            draft = .init(title: plan.title, start: plan.start, end: plan.end, allDay: plan.allDay)
        } else {
            let now = Date()
            var start: Date
            if cal.isDate(selected, inSameDayAs: now) {
                let hour = cal.dateInterval(of: .hour, for: now)?.start ?? now
                start = cal.date(byAdding: .hour, value: 1, to: hour) ?? now
            } else {
                start = cal.date(byAdding: .hour, value: 9, to: selected) ?? selected
            }
            if !cal.isDate(start, inSameDayAs: selected) { start = selected }
            // Made from the calendar in a chat, it is most often for the
            // person the chat is with: it goes into the message once added.
            draft = .init(title: "", start: start, end: start.addingTimeInterval(3600), allDay: false,
                          share: true)
        }
        composer?.removeFromSuperview()
        let c = EventComposer(draft: draft, access: CalendarWriter.access(hasFullAccess: hasFullAccess))
        c.onCancel = { [weak self] in self?.closeComposer() }
        c.onAdd = { [weak self] d in self?.add(d) }
        c.onEditTitle = { [weak self] editor in self?.delegate?.connectorSearchActivated(editor) }
        c.onLayoutChange = { [weak self] in
            guard let self else { return }
            if self.composer?.editingTitle != true { self.delegate?.connectorSearchDismissed() }
            self.delegate?.connectorLayoutChanged()
        }
        c.onOpenApp = { [weak self] path in self?.delegate?.connectorOpenApp(path: path) }
        addSubview(c)
        composer = c
        // Laid out before it shows, so no control flashes at the corner.
        c.frame = bounds
        c.layoutIfNeeded()
        render()
        setNeedsLayout()
        delegate?.connectorLayoutChanged()
    }

    /// Book a time on the person's own page, or on someone else's (a link in
    /// the chat): then it starts from their own name and email in the vault.
    func openBooking(link other: String? = nil) {
        guard let link = other ?? bookingLink else { return }
        let fields = VaultStore.shared.load().fields
        let me = [fields.first(where: { $0.kind == "name" })?.value,
                  fields.first(where: { $0.kind == "email" })?.value].compactMap { $0 }.joined(separator: " ")
        let b = BookingSheet(link: link, day: selected, mine: other == nil, me: me)
        b.onBack = { [weak self] in
            self?.booking?.removeFromSuperview()
            self?.booking = nil
            self?.render()
        }
        b.onInsert = { [weak self] text in self?.delegate?.connectorInsert(text) }
        b.onEditWho = { [weak self] editor in self?.delegate?.connectorSearchActivated(editor) }
        b.onLayoutChange = { [weak self] in
            guard let self else { return }
            if self.booking?.editingWho != true { self.delegate?.connectorSearchDismissed() }
            self.delegate?.connectorLayoutChanged()
        }
        addSubview(b)
        booking = b
        b.frame = bounds
        b.layoutIfNeeded()
        render()
        setNeedsLayout()
    }

    /// A call link, straight into the message: the person's own Google Meet
    /// when Google is connected.
    private func insertCallLink() {
        callButton.isEnabled = false
        CallLink.make { [weak self] url, note in
            guard let self else { return }
            self.callButton.isEnabled = true
            self.delegate?.connectorInsert("Join me on a call: \(url)")
            if let note { self.delegate?.connectorToast(note) }
        }
    }

    /// "sam@x.com", "sam@x.com and ria@y.com", "sam@x.com and 2 others".
    private static func people(_ emails: [String]) -> String {
        switch emails.count {
        case 0: return ""
        case 1: return emails[0]
        case 2: return "\(emails[0]) and \(emails[1])"
        default: return "\(emails[0]) and \(emails.count - 1) others"
        }
    }

    private func closeComposer() {
        let wasEditing = composer?.editingTitle == true
        composer?.removeFromSuperview()
        composer = nil
        if wasEditing { delegate?.connectorSearchDismissed() }
        render()
        delegate?.connectorLayoutChanged()
    }

    /// With Google Calendar connected the event goes there, where Google
    /// emails the invitees and makes the Meet call; otherwise the phone's
    /// calendar takes it. Either way Share in chat puts it in the message.
    private func add(_ d: EventComposer.Draft) {
        guard !adding else { return }
        adding = true
        guard GoogleAccess.hasCalendar else { return saveHere(d, note: nil) }
        GoogleClient.shared.addEvent(title: d.title, start: d.start, end: d.end, allDay: d.allDay,
                                     guests: d.invitees, video: d.videoCall) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let added):
                self.adding = false
                self.addedToGoogle(d, meet: added.meet)
            case .failure(let failure):
                // Not lost: the phone's calendar takes it, and the toast says
                // why Google didn't (and so nobody was emailed).
                self.saveHere(d, note: GoogleClient.say(failure))
            }
        }
    }

    private func saveHere(_ d: EventComposer.Draft, note: String?) {
        guard d.videoCall else {
            adding = false
            return save(d, callLink: nil, note: note)
        }
        // The call link first, so the event carries it and so does the message.
        CallLink.make { [weak self] url, meetNote in
            self?.adding = false
            self?.save(d, callLink: url, note: note ?? meetNote)
        }
    }

    private func addedToGoogle(_ d: EventComposer.Draft, meet: String?) {
        let said = d.invitees.isEmpty ? "Added to Google Calendar"
            : "Added. Google emailed the invite to \(Self.people(d.invitees))"
        if d.share {
            closeComposer()
            let event = CalendarText.Event(title: d.title, start: d.start, end: d.end, allDay: d.allDay,
                                           location: meet, color: nil)
            delegate?.connectorInsert(CalendarText.insert(event, calendar: cal))
            delegate?.connectorToast(said)
            return
        }
        // Google's calendar reaches the phone's on its next sync: show the day.
        selected = cal.startOfDay(for: d.start)
        month = cal.date(from: cal.dateComponents([.year, .month], from: selected)) ?? month
        showingMonth = false
        closeComposer()
        load()
        render()
        KeyboardToast.show(in: self, text: said)
    }

    private func save(_ d: EventComposer.Draft, callLink: String?, note: String?) {
        let notes = callLink.map { "Join the call: \($0)" }
        switch CalendarWriter.add(title: d.title, start: d.start, end: d.end, allDay: d.allDay,
                                  location: callLink, url: callLink.flatMap(URL.init(string:)), notes: notes) {
        case .success(let added):
            let said = "Added to \(added.calendarName)" + (note.map { ". \($0)" } ?? "")
            if d.share {
                closeComposer()
                delegate?.connectorInsert(CalendarText.insert(added.event, calendar: cal))
                delegate?.connectorToast(said)
                return
            }
            selected = cal.startOfDay(for: d.start)
            month = cal.date(from: cal.dateComponents([.year, .month], from: selected)) ?? month
            showingMonth = false
            justAdded = added.event
            closeComposer()
            load()
            render()
            KeyboardToast.show(in: self, text: said)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.justAdded = nil
                self?.litRow?.layer.borderWidth = 0
            }
        case .failure(.noCalendar):
            KeyboardToast.show(in: self, text: "No calendar to add it to")
        case .failure(.saveFailed):
            KeyboardToast.show(in: self, text: "Couldn't add the event. Try again")
        }
    }

    // MARK: build

    private func build() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Glass.textPrimary
        addSubview(titleLabel)

        for (button, symbol, id, step) in [(prevButton, "chevron.left", "calendar:prev", -1),
                                           (nextButton, "chevron.right", "calendar:next", 1)] {
            button.setImage(UIImage(systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)), for: .normal)
            button.tintColor = Glass.textPrimary
            button.accessibilityIdentifier = id
            button.addAction(UIAction { [weak self] _ in self?.step(step) }, for: .touchUpInside)
            addSubview(button)
        }

        modeButton.accessibilityIdentifier = "calendar:month"
        modeButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        modeButton.setTitleColor(Glass.textPrimary, for: .normal)
        modeButton.tintColor = Glass.textPrimary
        modeButton.backgroundColor = Glass.surfaceCard
        modeButton.layer.cornerCurve = .continuous
        modeButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 11, bottom: 0, right: 11)
        modeButton.addAction(UIAction { [weak self] _ in self?.toggleMonth() }, for: .touchUpInside)
        addSubview(modeButton)

        // Calendar's own + for a new event, at the end of the header.
        newButton.setImage(UIImage(systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        newButton.tintColor = Glass.textPrimary
        newButton.backgroundColor = Glass.surfaceCard
        newButton.accessibilityIdentifier = "calendar:new"
        newButton.accessibilityLabel = "New event"
        newButton.addAction(UIAction { [weak self] _ in self?.compose() }, for: .touchUpInside)
        addSubview(newButton)

        // A call link for the chat, without making an event.
        callButton.setImage(UIImage(systemName: "video",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)), for: .normal)
        callButton.tintColor = Glass.textPrimary
        callButton.backgroundColor = Glass.surfaceCard
        callButton.accessibilityIdentifier = "calendar:call"
        callButton.accessibilityLabel = "Send a call link"
        callButton.addAction(UIAction { [weak self] _ in self?.insertCallLink() }, for: .touchUpInside)
        addSubview(callButton)

        styleAction(bookButton, title: "Book a time")
        bookButton.backgroundColor = Glass.surfaceCard
        bookButton.setTitleColor(Glass.textPrimary, for: .normal)
        bookButton.accessibilityIdentifier = "calendar:book"
        bookButton.addAction(UIAction { [weak self] _ in self?.openBooking() }, for: .touchUpInside)
        addSubview(bookButton)

        let symbols = cal.veryShortStandaloneWeekdaySymbols
        for i in 0..<7 {
            let l = UILabel()
            l.text = symbols[(i + cal.firstWeekday - 1) % 7]
            l.font = .systemFont(ofSize: 11, weight: .semibold)
            l.textColor = Glass.textSecondary
            l.textAlignment = .center
            addSubview(l)
            weekdayLabels.append(l)
        }

        for i in 0..<42 {
            let b = UIButton(type: .custom)
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
            b.layer.cornerCurve = .continuous
            b.addAction(UIAction { [weak self] _ in self?.tapDay(i) }, for: .touchUpInside)
            let dot = UIView()
            dot.isUserInteractionEnabled = false
            dot.layer.cornerRadius = 2
            b.addSubview(dot)
            addSubview(b)
            dayButtons.append(b)
            dayDots.append(dot)
        }

        agenda.showsVerticalScrollIndicator = false
        agendaStack.axis = .vertical
        agendaStack.spacing = 8
        agenda.addSubview(agendaStack)
        addSubview(agenda)

        styleAction(freeButton, title: "Share free time")
        freeButton.accessibilityIdentifier = "calendar:free"
        freeButton.addAction(UIAction { [weak self] _ in self?.shareFree() }, for: .touchUpInside)
        addSubview(freeButton)

        // The day itself is the thing people most often type: "September 24".
        styleAction(dateButton, title: "Insert date")
        dateButton.backgroundColor = Glass.surfaceCard
        dateButton.setTitleColor(Glass.textPrimary, for: .normal)
        dateButton.accessibilityIdentifier = "calendar:date"
        dateButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.connectorInsert(Self.dateText(self.selected))
        }, for: .touchUpInside)
        addSubview(dateButton)

        styleAction(connectButton, title: "Connect calendar")
        connectButton.accessibilityIdentifier = "calendar:connect"
        connectButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.connectorOpenApp(path: "connected")
        }, for: .touchUpInside)
        addSubview(connectButton)
    }

    private func styleAction(_ b: UIButton, title: String) {
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = Glass.accentPrimary
        b.layer.cornerCurve = .continuous
    }

    // MARK: behaviour

    /// The arrows walk days on the list, months on the grid.
    private func step(_ direction: Int) {
        if showingMonth {
            guard let m = cal.date(byAdding: .month, value: direction, to: month) else { return }
            month = m
            if live { load() }
        } else {
            guard let d = cal.date(byAdding: .day, value: direction, to: selected) else { return }
            selected = d
            let m = cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? month
            if m != month {
                month = m
                if live { load() }
            }
        }
        render()
    }

    private func toggleMonth() {
        showingMonth.toggle()
        if showingMonth {
            month = cal.date(from: cal.dateComponents([.year, .month], from: selected)) ?? month
        }
        render()
    }

    private func dayFor(cell i: Int) -> Date? {
        let weekday = cal.component(.weekday, from: month)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        let days = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let n = i - offset
        guard n >= 0, n < days else { return nil }
        return cal.date(byAdding: .day, value: n, to: month)
    }

    /// Picking a day is what the grid is for, so it closes behind you.
    private func tapDay(_ i: Int) {
        guard let d = dayFor(cell: i) else { return }
        selected = d
        showingMonth = false
        render()
    }

    private func shareFree() {
        delegate?.connectorInsert(CalendarText.freeTime(on: selected, in: events, calendar: cal))
    }

    /// "September 24", in the phone's own order for month and day.
    static func dateText(_ day: Date, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("MMMM d")
        return f.string(from: day)
    }

    // MARK: render

    private func render() {
        let composing = composer != nil || booking != nil
        for v in [titleLabel, prevButton, nextButton, modeButton, newButton, callButton, agenda] as [UIView] {
            v.isHidden = composing
        }
        bookButton.isHidden = composing || showingMonth || bookingLink == nil
        guard !composing else {
            weekdayLabels.forEach { $0.isHidden = true }
            dayButtons.forEach { $0.isHidden = true }
            freeButton.isHidden = true
            connectButton.isHidden = true
            dateButton.isHidden = true
            setNeedsLayout()
            return
        }
        let monthFormat = DateFormatter()
        monthFormat.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        titleLabel.text = showingMonth ? monthFormat.string(from: month) : CalendarText.dayLabel(selected)
        prevButton.accessibilityLabel = showingMonth ? "Previous month" : "Previous day"
        nextButton.accessibilityLabel = showingMonth ? "Next month" : "Next day"
        modeButton.setTitle(showingMonth ? "Done" : "Month", for: .normal)
        modeButton.accessibilityLabel = showingMonth ? "Close the month" : "Open the month"

        let today = cal.startOfDay(for: Date())
        let dayNumber = DateFormatter()
        dayNumber.dateFormat = "d"
        let idFormat = DateFormatter()
        idFormat.dateFormat = "yyyy-MM-dd"
        for (i, b) in dayButtons.enumerated() {
            guard showingMonth, let d = dayFor(cell: i) else {
                b.isHidden = true
                continue
            }
            b.isHidden = false
            let isToday = cal.isDate(d, inSameDayAs: today)
            let isSelected = cal.isDate(d, inSameDayAs: selected)
            b.setTitle(dayNumber.string(from: d), for: .normal)
            b.setTitleColor(isToday ? .white : Glass.textPrimary, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: isToday || isSelected ? .semibold : .regular)
            b.backgroundColor = isToday ? Glass.accentPrimary : (isSelected ? Glass.fillSoft : .clear)
            b.accessibilityIdentifier = "calendar:day:\(idFormat.string(from: d))"
            b.accessibilityLabel = CalendarText.dayLabel(d)
            let has = !CalendarText.events(on: d, in: events, calendar: cal).isEmpty
            dayDots[i].isHidden = !has
            dayDots[i].backgroundColor = isToday ? .white : Glass.accentPrimary
        }
        weekdayLabels.forEach { $0.isHidden = !showingMonth }

        agendaStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let dayEvents = CalendarText.events(on: selected, in: events, calendar: cal)
        if connected && !showingMonth {
            if dayEvents.isEmpty {
                agendaStack.addArrangedSubview(note("Nothing planned"))
            }
            for (i, e) in dayEvents.enumerated() {
                let r = row(e, index: i)
                if let added = justAdded,
                   added.id.map({ $0 == e.id }) ?? (added.title == e.title && added.start == e.start) {
                    // What was just added, lit for a moment so the eye finds it.
                    r.layer.borderWidth = 1.5
                    r.layer.borderColor = Glass.accentPrimary.cgColor
                    // Said as well as shown, until the list is next drawn.
                    r.accessibilityValue = "Just added"
                    justAddedRow = r
                    litRow = r
                }
                agendaStack.addArrangedSubview(r)
            }
        } else if !showingMonth {
            // Not connected yet: say so, rather than leave a blank band
            // between the date and the button that fixes it.
            agendaStack.addArrangedSubview(note("Your calendar is not connected yet"))
        }
        agenda.isHidden = showingMonth
        freeButton.isHidden = !connected || showingMonth
        connectButton.isHidden = connected || showingMonth
        dateButton.isHidden = showingMonth
        dateButton.accessibilityLabel = "Insert \(Self.dateText(selected))"
        setNeedsLayout()
    }

    private func note(_ text: String) -> UIView {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 14)
        l.textColor = Glass.textSecondary
        l.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return l
    }

    private func row(_ e: CalendarText.Event, index: Int) -> UIView {
        let b = UIControl()
        b.backgroundColor = Glass.surfaceCard
        b.layer.cornerRadius = 12
        b.layer.cornerCurve = .continuous
        b.accessibilityIdentifier = "calendar:event:\(index)"
        b.isAccessibilityElement = true
        b.accessibilityTraits = .button
        b.accessibilityLabel = CalendarText.insert(e)
        b.addAction(UIAction { [weak self] _ in
            self?.delegate?.connectorInsert(CalendarText.insert(e))
        }, for: .touchUpInside)

        let bar = UIView()
        bar.backgroundColor = e.color.flatMap(UIColor.init(hexString:)) ?? Glass.accentPrimary
        bar.layer.cornerRadius = 2
        let start = UILabel()
        start.text = e.allDay ? "All day" : CalendarText.clock(e.start)
        start.font = .systemFont(ofSize: e.allDay ? 13 : 14, weight: .semibold)
        start.textColor = Glass.textPrimary
        let end = UILabel()
        end.text = e.allDay ? nil : CalendarText.clock(e.end)
        end.font = .systemFont(ofSize: 12, weight: .regular)
        end.textColor = Glass.textSecondary
        let title = UILabel()
        title.text = e.title
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = Glass.textPrimary
        let place = UILabel()
        place.text = e.location
        place.font = .systemFont(ofSize: 12.5)
        place.textColor = Glass.textSecondary
        for v in [bar, start, end, title, place] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.isUserInteractionEnabled = false
            b.addSubview(v)
        }
        let text = UIStackView(arrangedSubviews: [title, place])
        text.axis = .vertical
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false
        text.isUserInteractionEnabled = false
        place.isHidden = e.location == nil
        b.addSubview(text)
        NSLayoutConstraint.activate([
            b.heightAnchor.constraint(equalToConstant: 54),
            bar.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 8),
            bar.topAnchor.constraint(equalTo: b.topAnchor, constant: 9),
            bar.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -9),
            bar.widthAnchor.constraint(equalToConstant: 4),
            start.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 10),
            start.topAnchor.constraint(equalTo: b.topAnchor, constant: e.allDay ? 18 : 10),
            start.widthAnchor.constraint(equalToConstant: 66),
            end.leadingAnchor.constraint(equalTo: start.leadingAnchor),
            end.topAnchor.constraint(equalTo: start.bottomAnchor, constant: 1),
            text.leadingAnchor.constraint(equalTo: start.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -10),
            text.centerYAnchor.constraint(equalTo: b.centerYAnchor),
        ])
        return b
    }

    // MARK: layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 12
        let headerH: CGFloat = 32

        if let composer {
            composer.frame = bounds
            return
        }
        if let booking {
            booking.frame = bounds
            return
        }

        newButton.frame = CGRect(x: bounds.width - pad - 30, y: 1, width: 30, height: 30)
        newButton.layer.cornerRadius = 15
        callButton.frame = CGRect(x: newButton.frame.minX - 36, y: 1, width: 30, height: 30)
        callButton.layer.cornerRadius = 15
        let modeW: CGFloat = showingMonth ? 66 : 76
        modeButton.frame = CGRect(x: callButton.frame.minX - 6 - modeW, y: 1, width: modeW, height: 30)
        modeButton.layer.cornerRadius = 15
        nextButton.frame = CGRect(x: modeButton.frame.minX - 34, y: 1, width: 30, height: 30)
        prevButton.frame = CGRect(x: nextButton.frame.minX - 30, y: 1, width: 30, height: 30)
        titleLabel.frame = CGRect(x: pad, y: 1, width: max(0, prevButton.frame.minX - pad - 6), height: 30)

        if showingMonth {
            let weekdayH: CGFloat = 18
            let cellW = (bounds.width - pad * 2) / 7
            let gridTop = headerH + weekdayH + 2
            let cellH = max(26, (bounds.height - gridTop - 8) / 6)
            for (i, l) in weekdayLabels.enumerated() {
                l.frame = CGRect(x: pad + CGFloat(i) * cellW, y: headerH, width: cellW, height: weekdayH)
            }
            let side = min(cellW, cellH) - 4
            for (i, b) in dayButtons.enumerated() {
                let r = i / 7, c = i % 7
                let cx = pad + CGFloat(c) * cellW + cellW / 2
                let cy = gridTop + CGFloat(r) * cellH + cellH / 2
                b.frame = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
                b.layer.cornerRadius = side / 2
                dayDots[i].frame = CGRect(x: side / 2 - 2, y: side - 6, width: 4, height: 4)
            }
            return
        }

        let w = bounds.width - pad * 2
        let actionH: CGFloat = 38
        let actionY = bounds.height - actionH - 8
        // Pills on one row: the date on the left, the calendar's own action
        // (share free time, or connect), and Book a time with a booking link.
        if bookButton.isHidden {
            let dateW = ((w - 8) * 0.42).rounded()
            dateButton.frame = CGRect(x: pad, y: actionY, width: dateW, height: actionH)
            freeButton.frame = CGRect(x: pad + dateW + 8, y: actionY, width: w - dateW - 8, height: actionH)
        } else {
            let third = ((w - 16) / 3).rounded(.down)
            dateButton.frame = CGRect(x: pad, y: actionY, width: third, height: actionH)
            freeButton.frame = CGRect(x: pad + third + 8, y: actionY, width: third, height: actionH)
            bookButton.frame = CGRect(x: pad + (third + 8) * 2, y: actionY, width: w - (third + 8) * 2, height: actionH)
            for b in [dateButton, freeButton, bookButton] { b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold) }
        }
        for b in [dateButton, freeButton, bookButton] { b.layer.cornerRadius = actionH / 2 }
        connectButton.frame = freeButton.frame
        connectButton.layer.cornerRadius = actionH / 2
        agenda.frame = CGRect(x: pad, y: headerH + 2, width: w, height: max(0, actionY - headerH - 10))
        let stackH = agendaStack.systemLayoutSizeFitting(
            CGSize(width: w, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        agendaStack.frame = CGRect(x: 0, y: 0, width: w, height: stackH)
        agenda.contentSize = CGSize(width: w, height: stackH)
        if let row = justAddedRow {
            agendaStack.layoutIfNeeded()
            agenda.scrollRectToVisible(row.frame.insetBy(dx: 0, dy: -4), animated: false)
            justAddedRow = nil
        }
    }
}

private extension UIColor {
    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
