import UIKit

/// The keyboard's calendar: a month on the left, the chosen day on the right.
/// Tap an event to put it in the message, or share when you are free that
/// day. Events come from the phone's calendar through the app (calendar.json);
/// without them it is still a calendar, and offers to connect.
final class CalendarSurface: UIView {

    weak var delegate: ConnectorSurfaceDelegate?

    private let cal = Calendar.current
    private var events: [CalendarText.Event] = []
    private var connected = false
    private var month: Date
    private var selected: Date

    private let monthLabel = UILabel()
    private let prevButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private var weekdayLabels: [UILabel] = []
    private var dayButtons: [UIButton] = []
    /// The event dot under each day (kept apart from the buttons' tags).
    private var dayDots: [UIView] = []
    private let divider = UIView()

    private let dayTitle = UILabel()
    private let agenda = UIScrollView()
    private let agendaStack = UIStackView()
    private let freeButton = UIButton(type: .system)
    private let connectButton = UIButton(type: .system)

    override init(frame: CGRect) {
        let today = Calendar.current.startOfDay(for: Date())
        month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
        selected = today
        super.init(frame: frame)
        backgroundColor = .clear
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
        monthLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        monthLabel.textColor = Glass.textPrimary
        addSubview(monthLabel)

        for (button, symbol, id, step) in [(prevButton, "chevron.left", "calendar:prev", -1),
                                           (nextButton, "chevron.right", "calendar:next", 1)] {
            button.setImage(UIImage(systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)), for: .normal)
            button.tintColor = Glass.textPrimary
            button.accessibilityIdentifier = id
            button.accessibilityLabel = step < 0 ? "Previous month" : "Next month"
            button.addAction(UIAction { [weak self] _ in self?.shiftMonth(step) }, for: .touchUpInside)
            addSubview(button)
        }

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
            b.titleLabel?.font = .systemFont(ofSize: 14.5, weight: .regular)
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

        divider.backgroundColor = Glass.strokeHairline
        addSubview(divider)

        dayTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        dayTitle.textColor = Glass.textPrimary
        addSubview(dayTitle)

        agenda.showsVerticalScrollIndicator = false
        agendaStack.axis = .vertical
        agendaStack.spacing = 6
        agenda.addSubview(agendaStack)
        addSubview(agenda)

        styleAction(freeButton, title: "Share free time", filled: true)
        freeButton.accessibilityIdentifier = "calendar:free"
        freeButton.addAction(UIAction { [weak self] _ in self?.shareFree() }, for: .touchUpInside)
        addSubview(freeButton)

        styleAction(connectButton, title: "Connect calendar", filled: true)
        connectButton.accessibilityIdentifier = "calendar:connect"
        connectButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.connectorOpenApp(path: "connected")
        }, for: .touchUpInside)
        addSubview(connectButton)
    }

    private func styleAction(_ b: UIButton, title: String, filled: Bool) {
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
        b.setTitleColor(filled ? .white : Glass.textPrimary, for: .normal)
        b.backgroundColor = filled ? Glass.accentPrimary : Glass.surfaceCard
        b.layer.cornerCurve = .continuous
    }

    // MARK: behaviour

    private func shiftMonth(_ step: Int) {
        guard let m = cal.date(byAdding: .month, value: step, to: month) else { return }
        month = m
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

    private func tapDay(_ i: Int) {
        guard let d = dayFor(cell: i) else { return }
        selected = d
        render()
    }

    private func shareFree() {
        delegate?.connectorInsert(CalendarText.freeTime(on: selected, in: events, calendar: cal))
    }

    // MARK: render

    private func render() {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        monthLabel.text = f.string(from: month)
        let today = cal.startOfDay(for: Date())
        let dayNumber = DateFormatter()
        dayNumber.dateFormat = "d"
        let idFormat = DateFormatter()
        idFormat.dateFormat = "yyyy-MM-dd"
        for (i, b) in dayButtons.enumerated() {
            guard let d = dayFor(cell: i) else {
                b.isHidden = true
                continue
            }
            b.isHidden = false
            let isToday = cal.isDate(d, inSameDayAs: today)
            let isSelected = cal.isDate(d, inSameDayAs: selected)
            b.setTitle(dayNumber.string(from: d), for: .normal)
            b.setTitleColor(isToday ? .white : Glass.textPrimary, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 14.5, weight: isToday || isSelected ? .semibold : .regular)
            b.backgroundColor = isToday ? Glass.accentPrimary : (isSelected ? Glass.fillSoft : .clear)
            b.accessibilityIdentifier = "calendar:day:\(idFormat.string(from: d))"
            b.accessibilityLabel = CalendarText.dayLabel(d)
            let has = !CalendarText.events(on: d, in: events, calendar: cal).isEmpty
            dayDots[i].isHidden = !has
            dayDots[i].backgroundColor = isToday ? .white : Glass.accentPrimary
        }

        dayTitle.text = CalendarText.dayLabel(selected)
        agendaStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let dayEvents = CalendarText.events(on: selected, in: events, calendar: cal)
        if connected {
            if dayEvents.isEmpty {
                agendaStack.addArrangedSubview(note("Nothing planned"))
            }
            for (i, e) in dayEvents.enumerated() {
                agendaStack.addArrangedSubview(row(e, index: i))
            }
        }
        freeButton.isHidden = !connected
        connectButton.isHidden = connected
        setNeedsLayout()
    }

    private func note(_ text: String) -> UIView {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 13)
        l.textColor = Glass.textSecondary
        return l
    }

    private func row(_ e: CalendarText.Event, index: Int) -> UIView {
        let b = UIControl()
        b.backgroundColor = Glass.surfaceCard
        b.layer.cornerRadius = 10
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
        bar.layer.cornerRadius = 1.5
        bar.isUserInteractionEnabled = false
        let time = UILabel()
        time.text = e.allDay ? "All day" : CalendarText.clock(e.start)
        time.font = .systemFont(ofSize: 11, weight: .medium)
        time.textColor = Glass.textSecondary
        let title = UILabel()
        title.text = e.title
        title.font = .systemFont(ofSize: 13.5, weight: .semibold)
        title.textColor = Glass.textPrimary
        for v in [bar, time, title] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.isUserInteractionEnabled = false
            b.addSubview(v)
        }
        NSLayoutConstraint.activate([
            b.heightAnchor.constraint(equalToConstant: 42),
            bar.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 7),
            bar.topAnchor.constraint(equalTo: b.topAnchor, constant: 8),
            bar.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -8),
            bar.widthAnchor.constraint(equalToConstant: 3),
            time.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 7),
            time.topAnchor.constraint(equalTo: b.topAnchor, constant: 5),
            time.trailingAnchor.constraint(lessThanOrEqualTo: b.trailingAnchor, constant: -6),
            title.leadingAnchor.constraint(equalTo: time.leadingAnchor),
            title.topAnchor.constraint(equalTo: time.bottomAnchor, constant: 1),
            title.trailingAnchor.constraint(lessThanOrEqualTo: b.trailingAnchor, constant: -6),
        ])
        return b
    }

    // MARK: layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 10
        let leftW = min(bounds.width * 0.56, 7 * 34 + pad * 2)
        let headerH: CGFloat = 30
        let weekdayH: CGFloat = 16
        let cellW = (leftW - pad * 2) / 7
        let gridTop = headerH + weekdayH + 2
        let cellH = max(22, min(cellW, (bounds.height - gridTop - 6) / 6))

        monthLabel.frame = CGRect(x: pad + 4, y: 2, width: leftW - 80, height: 26)
        nextButton.frame = CGRect(x: leftW - pad - 30, y: 0, width: 30, height: 30)
        prevButton.frame = CGRect(x: nextButton.frame.minX - 32, y: 0, width: 30, height: 30)
        for (i, l) in weekdayLabels.enumerated() {
            l.frame = CGRect(x: pad + CGFloat(i) * cellW, y: headerH, width: cellW, height: weekdayH)
        }
        let side = min(cellW, cellH) - 3
        for (i, b) in dayButtons.enumerated() {
            let r = i / 7, c = i % 7
            let cx = pad + CGFloat(c) * cellW + cellW / 2
            let cy = gridTop + CGFloat(r) * cellH + cellH / 2
            b.frame = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
            b.layer.cornerRadius = side / 2
            dayDots[i].frame = CGRect(x: side / 2 - 2, y: side - 5, width: 4, height: 4)
        }

        divider.frame = CGRect(x: leftW, y: 8, width: Glass.hairlineWidth, height: bounds.height - 16)

        let rx = leftW + pad
        let rw = bounds.width - rx - pad
        dayTitle.frame = CGRect(x: rx, y: 4, width: rw, height: 22)
        let actionH: CGFloat = 34
        let actionY = bounds.height - actionH - 8
        freeButton.frame = CGRect(x: rx, y: actionY, width: rw, height: actionH)
        freeButton.layer.cornerRadius = actionH / 2
        connectButton.frame = freeButton.frame
        connectButton.layer.cornerRadius = actionH / 2
        agenda.frame = CGRect(x: rx, y: 30, width: rw, height: max(0, actionY - 36))
        let stackH = agendaStack.systemLayoutSizeFitting(
            CGSize(width: rw, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        agendaStack.frame = CGRect(x: 0, y: 0, width: rw, height: stackH)
        agenda.contentSize = CGSize(width: rw, height: stackH)
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
