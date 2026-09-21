import UIKit

/// The keyboard's calendar: the day's events, full width, because that is
/// what you reach for mid-message. Tap one to put it in the message, or share
/// when you are free that day. Month opens the grid to jump to another day.
/// Events come from the phone's calendar through the app (calendar.json);
/// without them it is still a calendar, and offers to connect.
final class CalendarSurface: UIView {

    weak var delegate: ConnectorSurfaceDelegate?

    private let cal = Calendar.current
    private var events: [CalendarText.Event] = []
    private var connected = false
    private var month: Date
    private var selected: Date

    /// The grid is a detour for picking another day; the events are the point.
    private var showingMonth = false

    private let titleLabel = UILabel()
    private let prevButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private var weekdayLabels: [UILabel] = []
    private var dayButtons: [UIButton] = []
    /// The event dot under each day (kept apart from the buttons' tags).
    private var dayDots: [UIView] = []

    private let agenda = UIScrollView()
    private let agendaStack = UIStackView()
    private let freeButton = UIButton(type: .system)
    private let connectButton = UIButton(type: .system)

    override init(frame: CGRect) {
        let today = Calendar.current.startOfDay(for: Date())
        month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
        selected = today
        super.init(frame: frame)
        backgroundColor = Glass.touchableGrid
        load()
        build()
        render()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func load() {
        let json = AppGroupStore.readJSON(name: "calendar.json")
        connected = json != nil
        events = CalendarText.events(fromJSON: json)
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
        } else {
            guard let d = cal.date(byAdding: .day, value: direction, to: selected) else { return }
            selected = d
            month = cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? month
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

    // MARK: render

    private func render() {
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
                agendaStack.addArrangedSubview(row(e, index: i))
            }
        }
        agenda.isHidden = showingMonth
        freeButton.isHidden = !connected || showingMonth
        connectButton.isHidden = connected || showingMonth
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

        let modeW: CGFloat = showingMonth ? 66 : 76
        modeButton.frame = CGRect(x: bounds.width - pad - modeW, y: 1, width: modeW, height: 30)
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
        freeButton.frame = CGRect(x: pad, y: actionY, width: w, height: actionH)
        freeButton.layer.cornerRadius = actionH / 2
        connectButton.frame = freeButton.frame
        connectButton.layer.cornerRadius = actionH / 2
        agenda.frame = CGRect(x: pad, y: headerH + 2, width: w, height: max(0, actionY - headerH - 10))
        let stackH = agendaStack.systemLayoutSizeFitting(
            CGSize(width: w, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        agendaStack.frame = CGRect(x: 0, y: 0, width: w, height: stackH)
        agenda.contentSize = CGSize(width: w, height: stackH)
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
