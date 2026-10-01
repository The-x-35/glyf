import UIKit

/// The keyboard's calendar: the day's events, full width, because that is
/// what you reach for mid-message. Tap one to put it in the message, or share
/// when you are free that day. Month opens the grid to jump to another day.
/// Events come straight from the phone's calendar when the keyboard may read
/// it (Full Access, and the app allowed), else from the app's copy
/// (calendar.json); without either it is still a calendar, and offers to
/// connect. + opens New Event (EventComposer). Holding an event opens the
/// clipboard's kind of menu: Edit (the composer, as Edit Event) and Delete.
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
    /// The event just added (or changed), drawn out for a moment in the day's list.
    private var justAdded: CalendarText.Event?
    /// What its row says while it is lit.
    private var justSaid = "Just added"
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
    private let dateButton = UIButton(type: .system)

    init(hasFullAccess: Bool = false) {
        let today = Calendar.current.startOfDay(for: Date())
        month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
        selected = today
        self.hasFullAccess = hasFullAccess
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid
        // Google connected: its last answer for THIS account at once, then
        // ask again; the iPhone's own calendars show from the start.
        if GoogleAccess.hasCalendar {
            let email = GoogleAccess.load()?.email
            googleFetched = GoogleCache.load(for: email)?.events
            googleNote = "Google Calendar\(email.map { " · \($0)" } ?? "") · syncing…"
        }
        load()
        build()
        render()
        refreshGoogle()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Google's list for the window on screen, once it has answered; the
    /// window it covers, so month steps only refetch when they leave it.
    private var googleFetched: [CalendarText.Event]?
    private var googleWindow: (from: Date, to: Date)?
    /// How the last ask went, said under the day's events: when it synced,
    /// or what Google refused (it used to fail in silence).
    private var googleNote: String?
    private func load() {
        var base: [CalendarText.Event]
        if CalendarWriter.access(hasFullAccess: hasFullAccess) == .ready, CalendarWriter.canRead {
            live = true
            connected = true
            let from = cal.date(byAdding: .day, value: -7, to: month) ?? month
            let to = cal.date(byAdding: .day, value: 45, to: month) ?? month
            base = CalendarWriter.events(from: from, to: to)
        } else {
            let json = AppGroupStore.readJSON(name: "calendar.json")
            connected = connected || json != nil
            base = CalendarText.events(fromJSON: json)
        }
        // Google connected: that account's calendar, live from Google, over
        // the iPhone's own calendars. iCloud and the rest stay; the iPhone's
        // (possibly stale) copy of that same Google account gives way, so an
        // event changed or deleted on the web never shows twice or late.
        if GoogleAccess.hasCalendar, let google = googleFetched {
            connected = true
            base = CalendarText.withGoogle(google, over: base, primary: GoogleAccess.load()?.email, calendar: cal)
        }
        events = GoogleAdded.merged(into: base).filter { !isGone($0) }
    }

    /// Asks Google for the window on screen. The phone's calendar only has
    /// what iOS has synced (or nothing, when the Google account isn't on
    /// the phone); the list is what Google has NOW.
    private func refreshGoogle() {
        guard GoogleAccess.hasCalendar else { return }
        let from = cal.date(byAdding: .day, value: -7, to: month) ?? month
        let to = cal.date(byAdding: .day, value: 45, to: month) ?? month
        if let window = googleWindow, window.from <= from, window.to >= to { return }
        GoogleClient.shared.listEvents(from: from, to: to) { [weak self] result in
            guard let self else { return }
            let email = GoogleAccess.load()?.email
            switch result {
            case .success(let list):
                self.googleWindow = (from, to)
                self.googleFetched = list
                GoogleCache.save(list, for: email)
                self.connected = true
                let time = DateFormatter()
                time.timeStyle = .short
                self.googleNote = "Google Calendar\(email.map { " · \($0)" } ?? "") · updated \(time.string(from: Date()))"
            case .failure(let failure):
                // Nothing new from Google: its last answer stays when there is
                // one, beside the iPhone's own calendars.
                self.googleNote = "Google Calendar didn't sync: \(GoogleClient.say(failure))"
                    + (self.googleFetched != nil ? ". Showing the last sync" : "")
            }
            self.load()
            self.render()
        }
    }

    /// The list on `day`: where a plan is for, and where an event lands once added.
    private func show(day: Date) {
        selected = cal.startOfDay(for: day)
        month = cal.date(from: cal.dateComponents([.year, .month], from: selected)) ?? month
        showingMonth = false
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
            // The event, with its call link, goes into the message once added,
            // as one made from the calendar does: the plan in the message
            // has no link yet. Its day is the calendar's, so Cancel shows what
            // else is on then.
            draft = .init(title: plan.title, start: plan.start, end: plan.end, allDay: plan.allDay,
                          share: true)
            show(day: plan.start)
            load()
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
        // With Google Calendar connected the event goes to Google, so the
        // iPhone's own calendar permission is not needed to add it.
        let access: CalendarWriter.Access = GoogleAccess.hasCalendar && hasFullAccess
            ? .ready : CalendarWriter.access(hasFullAccess: hasFullAccess)
        present(EventComposer(draft: draft, access: access)) {
            [weak self] d in self?.add(d)
        }
    }

    /// New Event or Edit Event over the calendar; `onSave` gets the event
    /// Add (or Save) was tapped on.
    private func present(_ c: EventComposer, onSave: @escaping (EventComposer.Draft) -> Void) {
        dismissMenu()
        composer?.removeFromSuperview()
        c.onCancel = { [weak self] in self?.closeComposer() }
        c.onAdd = onSave
        c.onEditTitle = { [weak self] editor in self?.delegate?.connectorSearchActivated(editor) }
        c.onLayoutChange = { [weak self] in
            guard let self else { return }
            if self.composer?.editingTitle != true { self.delegate?.connectorSearchDismissed() }
            self.delegate?.connectorLayoutChanged()
        }
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

    /// The person's own Google Meet link, straight into the message. Without
    /// Google connected the calendar stays open and says how to get one.
    private func insertCallLink() {
        callButton.isEnabled = false
        CallLink.make { [weak self] url, note in
            guard let self else { return }
            self.callButton.isEnabled = true
            if let url {
                self.delegate?.connectorInsert("Join me on a call: \(url)")
            } else if let note {
                KeyboardToast.show(in: self, text: note)
            }
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
                self.addedToGoogle(d, added: added)
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

    private func addedToGoogle(_ d: EventComposer.Draft, added: GoogleClient.Added) {
        let said = d.invitees.isEmpty ? "Added to Google Calendar"
            : "Added. Google emailed the invite to \(Self.people(d.invitees))"
        let event = CalendarText.Event(title: d.title, start: d.start, end: d.end, allDay: d.allDay,
                                       location: added.meet, color: nil,
                                       id: added.id.map { "google:\($0)" })
        // The phone's calendar gets it on Google's next sync; until then the
        // keyboard's list shows it anyway.
        GoogleAdded.remember(event)
        if d.share {
            closeComposer()
            delegate?.connectorInsert(CalendarText.insert(event, calendar: cal))
            delegate?.connectorToast(said)
            return
        }
        show(day: d.start)
        justAdded = event
        justSaid = "Just added"
        closeComposer()
        load()
        render()
        KeyboardToast.show(in: self, text: said)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.justAdded = nil
            self?.litRow?.layer.borderWidth = 0
        }
    }

    private func save(_ d: EventComposer.Draft, callLink: String?, note: String?) {
        let notes = callLink.map { "Join the call: \($0)" }
        switch CalendarWriter.add(title: d.title, start: d.start, end: d.end, allDay: d.allDay,
                                  location: callLink, url: callLink.flatMap(URL.init(string:)), notes: notes) {
        case .success(let added):
            // The note is a sentence of its own: it starts with a capital.
            let said = "Added to \(added.calendarName)"
                + (note.map { ". \($0.prefix(1).uppercased())\($0.dropFirst())" } ?? "")
            if d.share {
                closeComposer()
                delegate?.connectorInsert(CalendarText.insert(added.event, calendar: cal))
                delegate?.connectorToast(said)
                return
            }
            show(day: d.start)
            justAdded = added.event
            justSaid = "Just added"
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

        scrim.backgroundColor = Glass.scrim
        scrim.isHidden = true
        scrim.accessibilityIdentifier = "calendar:scrim"
        scrim.addAction(UIAction { [weak self] _ in self?.dismissMenu() }, for: .touchUpInside)
        addSubview(scrim)
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
            refreshGoogle()
        } else {
            guard let d = cal.date(byAdding: .day, value: direction, to: selected) else { return }
            selected = d
            let m = cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? month
            if m != month {
                month = m
                if live { load() }
                refreshGoogle()
            }
        }
        render()
    }

    private func toggleMonth() {
        showingMonth.toggle()
        // Either way the month on show is the chosen day's: Done after
        // browsing other months must not leave the day outside what's loaded.
        let dayMonth = cal.date(from: cal.dateComponents([.year, .month], from: selected)) ?? month
        if dayMonth != month {
            month = dayMonth
            load()
            refreshGoogle()
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
                // By id, or, once the phone's own copy has replaced the
                // keyboard's, by what it is and when.
                if let added = justAdded,
                   (added.id != nil && added.id == e.id) || (added.title == e.title && added.start == e.start) {
                    // What was just added, lit for a moment so the eye finds it.
                    r.layer.borderWidth = 1.5
                    r.layer.borderColor = Glass.accentPrimary.cgColor
                    // Said as well as shown, until the list is next drawn.
                    r.accessibilityValue = justSaid
                    justAddedRow = r
                    litRow = r
                }
                agendaStack.addArrangedSubview(r)
            }
            if let googleNote {
                let l = UILabel()
                l.text = googleNote
                l.font = .systemFont(ofSize: 12)
                l.textColor = Glass.textSecondary
                l.numberOfLines = 2
                l.accessibilityIdentifier = "calendar:google"
                agendaStack.addArrangedSubview(l)
            }
        } else if !showingMonth {
            // The app asks for the calendar (onboarding, or Connected tools
            // for someone who said "Not now"). Settings only lists Calendars
            // for Glyf once the app has asked, so a refusal is Settings' to
            // undo and a question never asked is the app's.
            agendaStack.addArrangedSubview(note(accessNote))
        }
        agenda.isHidden = showingMonth
        freeButton.isHidden = !connected || showingMonth
        dateButton.isHidden = showingMonth
        dateButton.accessibilityLabel = "Insert \(Self.dateText(selected))"
        setNeedsLayout()
    }

    /// Where the calendar is turned on, when the keyboard can't reach it.
    private var accessNote: String {
        CalendarWriter.access(hasFullAccess: hasFullAccess) == .needsFullAccess
            ? "Turn on Allow Full Access for Glyf in Settings"
            : CalendarWriter.neverAsked
                ? "Turn on Calendar in Glyf › Connected tools"
                : "Allow Calendars in Settings › Apps › Glyf"
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
        let b = EventRow(event: e)
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
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(rowHeld(_:)))
        hold.minimumPressDuration = 0.35
        b.addGestureRecognizer(hold)
        b.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Edit") { [weak self] _ in self?.edit(e); return true },
            UIAccessibilityCustomAction(name: "Delete") { [weak self, weak b] _ in
                if let b { self?.showMenu(for: b, confirming: true) }
                return true
            },
        ]

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

    // MARK: Hold menu (Edit · Delete), the clipboard's own

    private final class EventRow: UIControl {
        let event: CalendarText.Event
        init(event: CalendarText.Event) {
            self.event = event
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
    }

    private struct MenuRow {
        let symbol: String
        let title: String
        let id: String
        var destructive = false
        let action: () -> Void
    }

    private let scrim = UIControl()
    private var menu: UIView?
    private var liftedRow: UIView?
    /// Deleted here: kept off the list while the phone's own copy catches up.
    private var gone = Set<String>()

    private func goneKeys(_ e: CalendarText.Event) -> [String] {
        // A repeating event's occurrences share their UID; the start tells them apart.
        [e.id, e.external.map { "\($0)@\(e.start.timeIntervalSince1970)" }].compactMap { $0 }
    }

    private func isGone(_ e: CalendarText.Event) -> Bool {
        !gone.isEmpty && goneKeys(e).contains(where: gone.contains)
    }

    /// Why the event can't be changed from the keyboard, when it can't.
    private func refusal(_ e: CalendarText.Event) -> String? {
        guard hasFullAccess else { return "Turn on Allow Full Access for Glyf in Settings" }
        // Google's own are changed at Google; the rest in the phone's calendar.
        if e.googleID != nil { return nil }
        guard live else { return accessNote }
        return CalendarWriter.readOnly(e).map { "\($0) is read-only" }
    }

    @objc private func rowHeld(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let row = g.view as? EventRow else { return }
        showMenu(for: row)
    }

    private func showMenu(for row: EventRow, confirming: Bool = false) {
        let e = row.event
        if let refusal = refusal(e) {
            KeyboardToast.show(in: self, text: refusal)
            return
        }
        dismissMenu()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        scrim.frame = bounds
        scrim.isHidden = false
        bringSubviewToFront(scrim)
        // The held event stays bright above the scrim, where it was.
        let lifted = row.snapshotView(afterScreenUpdates: false) ?? UIView()
        lifted.frame = row.convert(row.bounds, to: self)
        lifted.isUserInteractionEnabled = false
        addSubview(lifted)
        liftedRow = lifted
        if confirming { return confirmDelete(e) }
        showMenuBox([
            MenuRow(symbol: "pencil", title: "Edit", id: "calendar:menu:edit") { [weak self] in
                self?.dismissMenu()
                self?.edit(e)
            },
            MenuRow(symbol: "trash", title: "Delete", id: "calendar:menu:delete", destructive: true) {
                [weak self] in self?.confirmDelete(e)
            },
        ])
    }

    /// Delete asks once more, the way Calendar does: an event can have guests.
    private func confirmDelete(_ e: CalendarText.Event) {
        showMenuBox([
            MenuRow(symbol: "trash", title: e.repeats ? "Delete This Event Only" : "Delete Event",
                    id: "calendar:menu:confirm", destructive: true) { [weak self] in
                self?.dismissMenu()
                self?.delete(e)
            },
            MenuRow(symbol: "xmark", title: "Cancel", id: "calendar:menu:cancel") { [weak self] in
                self?.dismissMenu()
            },
        ])
    }

    /// The menu under the held event when there is room, else over it.
    private func showMenuBox(_ rows: [MenuRow]) {
        menu?.removeFromSuperview()
        let anchor = liftedRow?.frame ?? CGRect(x: 0, y: bounds.midY, width: bounds.width, height: 0)
        // The button's own title font (the clipboard's rows), measured so
        // "Delete This Event Only" stays on one line.
        let font = UIFont.preferredFont(forTextStyle: .body)
        let widest = rows.map { ceil(($0.title as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0
        let menuW = min(bounds.width - 16, max(176, widest + 18 + 12 + 26 + 16)), rowH: CGFloat = 50
        let box = UIView()
        box.backgroundColor = Glass.surfaceCard
        box.layer.cornerRadius = 14
        box.layer.cornerCurve = .continuous
        box.layer.shadowColor = UIColor.black.cgColor
        box.layer.shadowOpacity = 0.14
        box.layer.shadowRadius = 14
        box.layer.shadowOffset = CGSize(width: 0, height: 4)
        for (i, row) in rows.enumerated() {
            let b = UIButton(type: .system)
            var cfg = UIButton.Configuration.plain()
            cfg.image = UIImage(systemName: row.symbol)
            cfg.title = row.title
            cfg.imagePadding = 16
            cfg.baseForegroundColor = row.destructive ? Glass.accentDanger : Glass.textPrimary
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 12)
            cfg.titleLineBreakMode = .byTruncatingTail
            b.configuration = cfg
            b.contentHorizontalAlignment = .leading
            b.frame = CGRect(x: 0, y: CGFloat(i) * rowH, width: menuW, height: rowH)
            b.accessibilityIdentifier = row.id
            let action = row.action
            b.addAction(UIAction { _ in action() }, for: .touchUpInside)
            box.addSubview(b)
            if i > 0 {
                let line = UIView(frame: CGRect(x: 0, y: CGFloat(i) * rowH, width: menuW, height: 0.5))
                line.backgroundColor = Glass.strokeHairline
                box.addSubview(line)
            }
        }
        let h = CGFloat(rows.count) * rowH
        let x = min(max(8, anchor.maxX - menuW), bounds.width - menuW - 8)
        var y = anchor.maxY + 6
        if y + h > bounds.height - 6 { y = anchor.minY - 6 - h }
        y = min(max(6, y), bounds.height - h - 6)
        box.frame = CGRect(x: x, y: y, width: menuW, height: h)
        addSubview(box)
        menu = box
    }

    private func dismissMenu() {
        menu?.removeFromSuperview()
        menu = nil
        liftedRow?.removeFromSuperview()
        liftedRow = nil
        scrim.isHidden = true
    }

    /// Edit Event: the composer on the event's own title and times.
    private func edit(_ e: CalendarText.Event) {
        let draft = EventComposer.Draft(title: e.title, start: e.start, end: e.end, allDay: e.allDay)
        // Google's own need only the network; the rest, the phone's calendar.
        let access: CalendarWriter.Access = e.googleID != nil
            ? (hasFullAccess ? .ready : .needsFullAccess)
            : CalendarWriter.access(hasFullAccess: hasFullAccess)
        present(EventComposer(draft: draft, access: access, edit: true)) { [weak self] d in
            self?.saveEdit(e, d)
        }
    }

    private func saveEdit(_ old: CalendarText.Event, _ d: EventComposer.Draft) {
        guard !adding else { return }
        guard let googleID = old.googleID else {
            switch CalendarWriter.update(old, title: d.title, start: d.start, end: d.end, allDay: d.allDay) {
            case .success(let changed): edited(changed)
            case .failure(let failure): KeyboardToast.show(in: self, text: Self.say(failure, doing: "save"))
            }
            return
        }
        adding = true
        GoogleClient.shared.updateEvent(id: googleID, title: d.title, start: d.start, end: d.end,
                                        allDay: d.allDay) { [weak self] result in
            guard let self else { return }
            self.adding = false
            switch result {
            case .success(let listed):
                var changed = listed ?? old
                if listed == nil {
                    changed.title = d.title
                    changed.start = d.start
                    changed.end = d.end
                    changed.allDay = d.allDay
                }
                if let fetched = self.googleFetched {
                    self.googleFetched = fetched.map { $0.id == old.id ? changed : $0 }
                    GoogleCache.save(self.googleFetched ?? [], for: GoogleAccess.load()?.email)
                }
                if let id = old.id { GoogleAdded.forget(id: id, with: changed) }
                self.edited(changed)
            case .failure(let failure):
                KeyboardToast.show(in: self, text: "Couldn't save it: \(GoogleClient.say(failure))")
            }
        }
    }

    private func edited(_ e: CalendarText.Event) {
        show(day: e.start)
        justAdded = e
        justSaid = "Just changed"
        closeComposer()
        load()
        render()
        KeyboardToast.show(in: self, text: "Saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.justAdded = nil
            self?.litRow?.layer.borderWidth = 0
        }
    }

    private func delete(_ e: CalendarText.Event) {
        guard let googleID = e.googleID else {
            switch CalendarWriter.remove(e) {
            case .success:
                load()
                render()
                KeyboardToast.show(in: self, text: "Event deleted")
            case .failure(let failure):
                if failure == .notFound {
                    load()
                    render()
                }
                KeyboardToast.show(in: self, text: Self.say(failure, doing: "delete"))
            }
            return
        }
        // Off the list at once; back, with Google's reason, if it says no.
        let keys = goneKeys(e)
        gone.formUnion(keys)
        load()
        render()
        GoogleClient.shared.deleteEvent(id: googleID) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                if let fetched = self.googleFetched {
                    self.googleFetched = fetched.filter { $0.id != e.id }
                    GoogleCache.save(self.googleFetched ?? [], for: GoogleAccess.load()?.email)
                }
                if let id = e.id { GoogleAdded.forget(id: id) }
                KeyboardToast.show(in: self, text: "Event deleted")
            case .failure(let failure):
                self.gone.subtract(keys)
                KeyboardToast.show(in: self, text: "Couldn't delete it: \(GoogleClient.say(failure))")
            }
            self.load()
            self.render()
        }
    }

    private static func say(_ failure: CalendarWriter.Change, doing: String) -> String {
        switch failure {
        case .readOnly(let name): return "\(name) is read-only"
        case .notFound: return "It's no longer in the calendar"
        case .failed: return "Couldn't \(doing) it. Try again"
        }
    }

    // MARK: layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 12
        let headerH: CGFloat = 32
        scrim.frame = bounds

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
