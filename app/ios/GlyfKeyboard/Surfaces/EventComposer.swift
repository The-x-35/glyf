import UIKit

/// New Event, the way Calendar's own sheet has it: Cancel, the name and Add
/// along the top, then rows that scroll: Title, Invitees, Starts, Ends, Video
/// call, All-day. The title takes a whole plan in one line ("Lunch with Sam
/// tomorrow 1pm") and fills the times from it; invitees are email addresses,
/// sent a calendar invite when the event is added. The date and time pills
/// open Apple's wheels in place of the rows.
final class EventComposer: UIView {

    struct Draft: Equatable {
        var title: String
        var start: Date
        var end: Date
        var allDay: Bool
        /// Make a call link and put it in the event (its location).
        var videoCall: Bool = false
        /// Emailed a calendar invite once the event is added.
        var invitees: [String] = []
    }

    var onCancel: (() -> Void)?
    var onAdd: ((Draft) -> Void)?
    /// A field is being typed: the keys should come up and feed the editor.
    var onEditTitle: ((InlineEditor) -> Void)?
    /// Typing ended, or the shape changed (strip, rows, wheels).
    var onLayoutChange: (() -> Void)?
    var onOpenApp: ((String) -> Void)?

    /// Height of the strip over the keys while a field is typed.
    static let editStripHeight: CGFloat = 92

    private enum Field { case title, invitees }
    private var editing: Field?
    /// A field is being typed (the title or the invitees).
    var editingTitle: Bool { editing != nil }
    let titleEditor = InlineEditor(placeholder: "Title")

    private let cal = Calendar.current
    private var draft: Draft
    /// Whatever the title said, so the rows and the event agree.
    private var typed = ""
    /// The invitees as typed ("sam@x.com, ria@y.com").
    private var inviteLine = ""
    private var picking: Picking?
    private enum Picking { case start, end }
    private var access: CalendarWriter.Access

    private let cancelButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)
    private let heading = UILabel()
    private let rows = UIScrollView()
    private let card = UIView()
    private let titleRow = UIControl()
    private let titleValue = UILabel()
    private let inviteRow = UIControl()
    private let inviteLabel = UILabel()
    private let inviteValue = UILabel()
    private let startsLabel = UILabel()
    private let endsLabel = UILabel()
    private let allDayLabel = UILabel()
    private let videoLabel = UILabel()
    private let startDate = UIButton(type: .custom)
    private let startTime = UIButton(type: .custom)
    private let endDate = UIButton(type: .custom)
    private let endTime = UIButton(type: .custom)
    private let allDaySwitch = UISwitch()
    private let videoSwitch = UISwitch()
    private var separators: [UIView] = []
    private let picker = UIDatePicker()
    private let hint = UILabel()
    private let note = UILabel()
    private let noteButton = UIButton(type: .system)

    init(draft: Draft, access: CalendarWriter.Access) {
        self.draft = draft
        self.access = access
        super.init(frame: .zero)
        typed = draft.title
        inviteLine = draft.invitees.joined(separator: " ")
        build()
        render()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: build

    private func build() {
        backgroundColor = .clear

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16)
        cancelButton.tintColor = Glass.accentPrimary
        cancelButton.accessibilityIdentifier = "event:cancel"
        cancelButton.addAction(UIAction { [weak self] _ in self?.cancelTapped() }, for: .touchUpInside)
        addSubview(cancelButton)

        heading.text = "New Event"
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        heading.textColor = Glass.textPrimary
        heading.textAlignment = .center
        addSubview(heading)

        addButton.setTitle("Add", for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        addButton.tintColor = Glass.accentPrimary
        addButton.accessibilityIdentifier = "event:add"
        addButton.addAction(UIAction { [weak self] _ in self?.addTapped() }, for: .touchUpInside)
        addSubview(addButton)

        rows.showsVerticalScrollIndicator = false
        addSubview(rows)
        card.backgroundColor = Glass.surfaceCard
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        rows.addSubview(card)

        for (row, id, field) in [(titleRow, "event:title", Field.title), (inviteRow, "event:invitees", .invitees)] {
            row.accessibilityIdentifier = id
            row.isAccessibilityElement = true
            row.accessibilityTraits = .button
            row.addAction(UIAction { [weak self] _ in self?.begin(field) }, for: .touchUpInside)
            card.addSubview(row)
        }
        titleValue.font = .systemFont(ofSize: 16)
        titleValue.isUserInteractionEnabled = false
        titleRow.addSubview(titleValue)

        for (label, text) in [(startsLabel, "Starts"), (endsLabel, "Ends"), (allDayLabel, "All-day"),
                              (videoLabel, "Video call"), (inviteLabel, "Invitees")] {
            label.text = text
            label.font = .systemFont(ofSize: 16)
            label.textColor = Glass.textPrimary
            label.isUserInteractionEnabled = false
            if label === inviteLabel { inviteRow.addSubview(label) } else { card.addSubview(label) }
        }
        inviteValue.font = .systemFont(ofSize: 15)
        inviteValue.textAlignment = .right
        inviteValue.lineBreakMode = .byTruncatingHead
        inviteValue.isUserInteractionEnabled = false
        inviteRow.addSubview(inviteValue)

        for (pill, id, which) in [(startDate, "event:starts:date", Picking.start), (startTime, "event:starts:time", .start),
                                  (endDate, "event:ends:date", .end), (endTime, "event:ends:time", .end)] {
            pill.titleLabel?.font = .systemFont(ofSize: 15)
            pill.setTitleColor(Glass.textPrimary, for: .normal)
            pill.backgroundColor = Glass.fillSoft
            pill.layer.cornerRadius = 7
            pill.layer.cornerCurve = .continuous
            pill.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            pill.accessibilityIdentifier = id
            pill.addAction(UIAction { [weak self] _ in self?.pick(which) }, for: .touchUpInside)
            card.addSubview(pill)
        }
        for (toggle, id) in [(allDaySwitch, "event:allday"), (videoSwitch, "event:video")] {
            toggle.accessibilityIdentifier = id
            toggle.onTintColor = Glass.accentPrimary
            card.addSubview(toggle)
        }
        allDaySwitch.addAction(UIAction { [weak self] _ in self?.allDayChanged() }, for: .valueChanged)
        videoSwitch.addAction(UIAction { [weak self] _ in
            self?.draft.videoCall = self?.videoSwitch.isOn ?? false
        }, for: .valueChanged)
        for _ in 0..<5 {
            let line = UIView()
            line.backgroundColor = Glass.strokeSeparator
            line.isUserInteractionEnabled = false
            card.addSubview(line)
            separators.append(line)
        }

        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 5
        picker.accessibilityIdentifier = "event:picker"
        picker.isHidden = true
        picker.addAction(UIAction { [weak self] _ in self?.pickerChanged() }, for: .valueChanged)
        addSubview(picker)

        titleEditor.accessibilityIdentifier = "event:title:field"
        titleEditor.showsEnd = true
        titleEditor.isHidden = true
        titleEditor.onChange = { [weak self] text in self?.fieldChanged(text) }
        addSubview(titleEditor)

        hint.font = .systemFont(ofSize: 13)
        hint.textColor = Glass.textSecondary
        hint.isHidden = true
        hint.accessibilityIdentifier = "event:hint"
        addSubview(hint)

        note.font = .systemFont(ofSize: 13)
        note.textColor = Glass.textSecondary
        note.numberOfLines = 2
        note.isHidden = true
        addSubview(note)
        noteButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        noteButton.tintColor = Glass.accentPrimary
        noteButton.accessibilityIdentifier = "event:open-app"
        noteButton.isHidden = true
        noteButton.addAction(UIAction { [weak self] _ in self?.onOpenApp?("connected") }, for: .touchUpInside)
        addSubview(noteButton)
    }

    // MARK: behaviour

    private func cancelTapped() {
        if picking != nil {
            picking = nil
            render()
            return
        }
        if editing != nil { endTitle() }
        onCancel?()
    }

    private func addTapped() {
        if picking != nil {
            // The wheels' own Done.
            picking = nil
            render()
            return
        }
        if editing != nil { endTitle() }
        guard access == .ready else { return }
        var d = draft
        d.title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.title.isEmpty { d.title = "New Event" }
        d.invitees = EventParse.people(inviteLine).emails
        onAdd?(d)
    }

    func beginTitle() { begin(.title) }

    private func begin(_ field: Field) {
        guard editing == nil else { return }
        editing = field
        picking = nil
        titleEditor.placeholder = field == .title ? "Title" : "Emails, with spaces between"
        titleEditor.accessibilityIdentifier = field == .title ? "event:title:field" : "event:invitees:field"
        titleEditor.setText(field == .title ? typed : inviteLine)
        titleEditor.isActive = true
        onEditTitle?(titleEditor)
        render()
        onLayoutChange?()
    }

    /// Return on the keys, or tapping away: back to the rows.
    func endTitle() {
        guard editing != nil else { return }
        editing = nil
        titleEditor.isActive = false
        render()
        onLayoutChange?()
    }

    private func fieldChanged(_ text: String) {
        if editing == .invitees {
            inviteLine = text
            draft.invitees = EventParse.people(text).emails
            render()
            return
        }
        // A plan typed into the title sets the times too ("tomorrow 1pm").
        typed = text
        let plan = EventParse.parse(text, calendar: cal, dayFirst: EventParse.regionDayFirst)
        if plan.hasDay || plan.hasTime || plan.allDay {
            draft.title = plan.title
            draft.start = plan.start
            draft.end = plan.end
            draft.allDay = plan.allDay
        } else {
            draft.title = text.trimmingCharacters(in: .whitespaces)
        }
        render()
    }

    private func pick(_ which: Picking) {
        if editing != nil { endTitle() }
        picking = which
        picker.datePickerMode = draft.allDay ? .date : .dateAndTime
        picker.date = which == .start ? draft.start : draft.end
        render()
    }

    private func pickerChanged() {
        guard let which = picking else { return }
        let date = picker.date
        if which == .start {
            // Moving the start carries the end along, keeping the length.
            let length = draft.end.timeIntervalSince(draft.start)
            draft.start = date
            draft.end = date.addingTimeInterval(max(length, draft.allDay ? 86_400 : 900))
        } else {
            draft.end = max(date, draft.start.addingTimeInterval(draft.allDay ? 0 : 900))
        }
        render()
    }

    private func allDayChanged() {
        draft.allDay = allDaySwitch.isOn
        if draft.allDay {
            draft.start = cal.startOfDay(for: draft.start)
            draft.end = cal.date(byAdding: .day, value: 1, to: draft.start) ?? draft.start
        } else {
            let base = cal.startOfDay(for: draft.start)
            draft.start = cal.date(byAdding: .hour, value: 9, to: base) ?? base
            draft.end = cal.date(byAdding: .hour, value: 1, to: draft.start) ?? draft.start
        }
        render()
    }

    // MARK: render

    private static func text(_ date: Date, template: String) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    /// "sam@x.com", "sam@x.com and 1 more", or "None".
    private static func people(_ emails: [String]) -> String {
        guard let first = emails.first else { return "None" }
        return emails.count == 1 ? first : "\(first) and \(emails.count - 1) more"
    }

    private func render() {
        let strip = editing != nil
        let rowsHidden = strip || picking != nil
        rows.isHidden = rowsHidden
        picker.isHidden = picking == nil
        hint.isHidden = !strip
        titleEditor.isHidden = !strip

        heading.text = picking == .start ? "Starts" : picking == .end ? "Ends" : "New Event"
        cancelButton.isHidden = picking != nil
        addButton.setTitle(picking != nil ? "Done" : "Add", for: .normal)
        addButton.accessibilityIdentifier = picking != nil ? "event:done" : "event:add"
        addButton.isEnabled = picking != nil || access == .ready
        addButton.alpha = addButton.isEnabled ? 1 : 0.4

        let title = draft.title.trimmingCharacters(in: .whitespaces)
        titleValue.text = title.isEmpty ? "Title" : title
        titleValue.textColor = title.isEmpty ? Glass.textSecondary : Glass.textPrimary
        titleRow.accessibilityLabel = title.isEmpty ? "Title" : "Title, \(title)"
        inviteValue.text = Self.people(draft.invitees)
        inviteValue.textColor = draft.invitees.isEmpty ? Glass.textSecondary : Glass.textPrimary
        inviteRow.accessibilityLabel = "Invitees, \(inviteValue.text ?? "")"

        let sameDay = cal.isDate(draft.start, inSameDayAs: draft.end)
            || (draft.allDay && cal.isDate(draft.start, inSameDayAs: draft.end.addingTimeInterval(-1)))
        startDate.setTitle(Self.text(draft.start, template: "EEE d MMM"), for: .normal)
        startTime.setTitle(Self.text(draft.start, template: "jmm"), for: .normal)
        endDate.setTitle(Self.text(draft.allDay ? draft.end.addingTimeInterval(-1) : draft.end,
                                   template: "EEE d MMM"), for: .normal)
        endTime.setTitle(Self.text(draft.end, template: "jmm"), for: .normal)
        startTime.isHidden = draft.allDay
        endTime.isHidden = draft.allDay
        endDate.isHidden = sameDay && !draft.allDay
        allDaySwitch.isOn = draft.allDay
        videoSwitch.isOn = draft.videoCall

        if editing == .invitees {
            hint.text = draft.invitees.isEmpty ? "They get an email invite when it's added"
                : "Invite \(draft.invitees.joined(separator: ", "))"
        } else {
            hint.text = draft.allDay
                ? Self.text(draft.start, template: "EEEE d MMMM")
                : "\(Self.text(draft.start, template: "EEE d MMM")), \(CalendarText.range(draft.start, draft.end))"
        }

        switch access {
        case .ready:
            note.isHidden = true
            noteButton.isHidden = true
        case .needsFullAccess:
            note.text = "Turn on Allow Full Access for Glyf in Settings to add events."
            noteButton.setTitle("How", for: .normal)
            note.isHidden = rowsHidden
            noteButton.isHidden = rowsHidden
        case .needsPermission:
            note.text = "Let Glyf use your calendar to add events."
            noteButton.setTitle("Connect", for: .normal)
            note.isHidden = rowsHidden
            noteButton.isHidden = rowsHidden
        }
        setNeedsLayout()
    }

    // MARK: layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let pad: CGFloat = 12

        if editing != nil {
            // The strip over the keys: Cancel, the field, Add; what it read below.
            let rowH: CGFloat = 38
            cancelButton.frame = CGRect(x: 4, y: 8, width: 66, height: rowH)
            addButton.frame = CGRect(x: w - 58, y: 8, width: 54, height: rowH)
            titleEditor.frame = CGRect(x: cancelButton.frame.maxX + 2, y: 8,
                                       width: addButton.frame.minX - cancelButton.frame.maxX - 6, height: rowH)
            heading.isHidden = true
            hint.frame = CGRect(x: titleEditor.frame.minX + 4, y: titleEditor.frame.maxY + 6,
                                width: titleEditor.frame.width, height: 18)
            return
        }
        heading.isHidden = false
        let headerH: CGFloat = bounds.height >= 240 ? 40 : 34
        cancelButton.frame = CGRect(x: 4, y: 0, width: 72, height: headerH)
        addButton.frame = CGRect(x: w - 64, y: 0, width: 60, height: headerH)
        heading.frame = CGRect(x: 80, y: 0, width: w - 160, height: headerH)

        if picking != nil {
            picker.frame = CGRect(x: pad, y: headerH, width: w - pad * 2, height: max(0, bounds.height - headerH - 4))
            return
        }

        let showNote = access != .ready
        // Five rows in view on the plain keyboard (All-day scrolls in under
        // them), Calendar's own 40pt wherever there is room.
        let rowH: CGFloat = max(34, min(40, floor((bounds.height - headerH - 6 - (showNote ? 44 : 0)) / 5)))
        // Without the calendar, only what can be seen is shown; the note says why.
        let order: [UIView] = showNote ? [titleRow, startsLabel, endsLabel]
                                       : [titleRow, inviteRow, startsLabel, endsLabel, videoLabel, allDayLabel]
        let noteH: CGFloat = showNote ? 44 : 0
        rows.frame = CGRect(x: pad, y: headerH + 2, width: w - pad * 2,
                            height: max(0, bounds.height - headerH - 6 - noteH))
        card.frame = CGRect(x: 0, y: 0, width: rows.bounds.width, height: rowH * CGFloat(order.count))
        rows.contentSize = card.frame.size
        let cw = card.bounds.width
        let rowY = { (v: UIView) -> CGFloat in rowH * CGFloat(order.firstIndex(where: { $0 === v }) ?? 0) }

        titleRow.frame = CGRect(x: 0, y: rowY(titleRow), width: cw, height: rowH)
        titleValue.frame = CGRect(x: 14, y: 0, width: cw - 28, height: rowH)
        inviteRow.isHidden = showNote
        inviteRow.frame = CGRect(x: 0, y: rowY(inviteRow), width: cw, height: rowH)
        inviteLabel.frame = CGRect(x: 14, y: 0, width: 90, height: rowH)
        inviteValue.frame = CGRect(x: 104, y: 0, width: cw - 118, height: rowH)

        func label(_ l: UILabel) { l.frame = CGRect(x: 14, y: rowY(l), width: 90, height: rowH) }
        label(startsLabel)
        label(endsLabel)
        let pillH: CGFloat = 30
        func place(_ pills: [UIButton], y: CGFloat) {
            var x = cw - 10
            for p in pills.reversed() where !p.isHidden {
                let pw = ceil(p.intrinsicContentSize.width)
                x -= pw
                p.frame = CGRect(x: x, y: y + (rowH - pillH) / 2, width: pw, height: pillH)
                x -= 6
            }
        }
        place([startDate, startTime], y: rowY(startsLabel))
        place([endDate, endTime], y: rowY(endsLabel))

        for v in [allDayLabel, allDaySwitch, videoLabel, videoSwitch] as [UIView] { v.isHidden = showNote }
        if !showNote {
            for (l, toggle) in [(videoLabel, videoSwitch), (allDayLabel, allDaySwitch)] {
                label(l)
                let s = toggle.intrinsicContentSize
                toggle.frame = CGRect(x: cw - s.width - 12, y: rowY(l) + (rowH - s.height) / 2,
                                      width: s.width, height: s.height)
            }
        }
        for (i, line) in separators.enumerated() {
            line.isHidden = i >= order.count - 1
            line.frame = CGRect(x: 14, y: rowH * CGFloat(i + 1) - 0.5, width: cw - 14, height: 0.5)
        }
        if showNote {
            let noteY = rows.frame.maxY + 4
            noteButton.sizeToFit()
            let bw = noteButton.bounds.width + 8
            noteButton.frame = CGRect(x: w - pad - bw, y: noteY, width: bw, height: 34)
            note.frame = CGRect(x: pad + 4, y: noteY, width: noteButton.frame.minX - pad - 10, height: 34)
        }
    }
}
