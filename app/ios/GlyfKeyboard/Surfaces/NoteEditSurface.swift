import UIKit

protocol NoteEditSurfaceDelegate: AnyObject {
    func noteEditActivated(_ editor: InlineEditor)
    func noteEditSaved()
    func noteEditClosed()
}

/// Adding to the vault WITHOUT leaving the keyboard: a strip above the letter
/// keys (same pattern as emoji search) — type, Save, done. A note (new, or
/// one held to edit), a detail of the kind picked in the vault, or a
/// shorthand: its shortcut, then what it types out. SecretScanner still
/// stands guard inside NotesStore and VaultRules.
final class NoteEditSurface: UIView {

    enum Edit {
        case note(id: String?, text: String)
        case detail(DetailKind)
        case shorthand
    }

    weak var delegate: NoteEditSurfaceDelegate?

    static let stripHeight: CGFloat = 96

    let edit: Edit
    /// The note, the detail, or what a shorthand types out.
    let editor: InlineEditor
    /// A shorthand's shortcut, typed first; nil for a note or a detail.
    private let shortcutEditor: InlineEditor?
    /// The one the keys type into.
    private(set) var activeEditor: InlineEditor
    private let closeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    init(edit: Edit) {
        self.edit = edit
        switch edit {
        case .note(_, let text):
            editor = InlineEditor(placeholder: "Write a note…")
            if !text.isEmpty { editor.append(text) }
            shortcutEditor = nil
        case .detail(let kind):
            // The kind's icon stays in the field once its name, the
            // placeholder, has given way to what is typed.
            editor = InlineEditor(placeholder: kind.title, symbol: kind.symbol)
            shortcutEditor = nil
        case .shorthand:
            editor = InlineEditor(placeholder: "Types out")
            // Every shortcut starts with a semicolon, which sits on another
            // page of keys: it is there already, as in the app.
            let shortcut = InlineEditor(placeholder: "Shortcut")
            shortcut.append(";")
            shortcutEditor = shortcut
        }
        activeEditor = shortcutEditor ?? editor
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid

        editor.accessibilityIdentifier = "noteedit:field"
        // The end stays in view, where the typing is.
        editor.showsEnd = true
        for field in [shortcutEditor, editor].compactMap({ $0 }) {
            field.isAccessibilityElement = true
            field.accessibilityLabel = field.placeholder
            field.accessibilityValue = field.text
            field.onChange = { [weak field] text in field?.accessibilityValue = text }
            field.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(fieldTapped(_:))))
            addSubview(field)
        }
        shortcutEditor?.accessibilityIdentifier = "noteedit:shortcut"
        shortcutEditor?.showsEnd = true

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.setPreferredSymbolConfiguration(.init(pointSize: 13, weight: .semibold),
                                                    forImageIn: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "noteedit:close"
        closeButton.accessibilityLabel = "Close"
        closeButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.noteEditClosed()
        }, for: .touchUpInside)
        addSubview(closeButton)

        saveButton.setTitle("Save", for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        // The ink's own pill, as the Ask bar's run button is: black on a
        // light sheet, white on a dark one (a black pill vanished there).
        saveButton.setTitleColor(Glass.isDark ? Glass.brandInk : .white, for: .normal)
        saveButton.backgroundColor = Glass.textPrimary
        saveButton.layer.cornerRadius = 15
        saveButton.layer.cornerCurve = .continuous
        saveButton.accessibilityIdentifier = "noteedit:save"
        saveButton.addAction(UIAction { [weak self] _ in self?.save() }, for: .touchUpInside)
        addSubview(saveButton)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = Glass.accentDanger
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.accessibilityIdentifier = "noteedit:status"
        addSubview(statusLabel)

        MemoryLogger.logSurface("noteedit")
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A phone number opens on the digits, as a phone field does.
    var wantsDigits: Bool {
        if case .detail(let kind) = edit { return kind.kind == "phone" }
        return false
    }

    /// An email or a link gets the keys its field would (@ and . on the
    /// space row, or / and .com), as the address in a form does (2026-10-14:
    /// a new email detail opened on plain letters, "@" two layers away).
    var keysContext: KeyboardContext? {
        guard case .detail(let kind) = edit else { return nil }
        switch kind.kind {
        case "email": return .email
        case "link": return .url
        default: return nil
        }
    }

    /// Whether the field being typed starts with a capital: a note, a name,
    /// an address or what a shorthand types out do; a shortcut, an email, a
    /// link or a wallet never do (";Sig" would never expand from ";sig").
    var startsWithCapital: Bool {
        guard activeEditor.text.isEmpty else { return false }
        switch edit {
        case .note: return true
        case .detail(let kind): return ["name", "address", "custom"].contains(kind.kind)
        case .shorthand: return activeEditor === editor
        }
    }

    @objc private func fieldTapped(_ g: UITapGestureRecognizer) {
        guard let field = g.view as? InlineEditor else { return }
        activate(field)
    }

    /// The keys type into this one from now on.
    func activate(_ field: InlineEditor) {
        for other in [shortcutEditor, editor].compactMap({ $0 }) where other !== field {
            other.isActive = false
        }
        field.isActive = true
        activeEditor = field
        delegate?.noteEditActivated(field)
    }

    /// Return: a new line in a note or in what a shorthand types out; from
    /// the shortcut on to what it types out; a detail is one line, so it is
    /// saved.
    func returnPressed() {
        switch edit {
        case .note:
            editor.append("\n")
        case .detail:
            save()
        case .shorthand:
            if activeEditor === shortcutEditor { activate(editor) } else { editor.append("\n") }
        }
    }

    private func save() {
        let text = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let refusal: String?
        switch edit {
        case .note(let id, _):
            refusal = NotesStore.shared.upsert(id: id, text: text)
        case .detail(let kind):
            refusal = VaultStore.shared.addField(kind: kind.kind, label: kind.label, value: text)
        case .shorthand:
            // "sig" typed over the semicolon still means ";sig".
            var trigger = (shortcutEditor?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trigger.hasPrefix(";") { trigger = ";" + trigger }
            refusal = VaultStore.shared.upsertSnippet(trigger: trigger, text: text)
        }
        if let refusal {
            statusLabel.text = refusal
            setNeedsLayout()
            return
        }
        delegate?.noteEditSaved()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        closeButton.frame = CGRect(x: 2, y: 8, width: 36, height: 34)
        saveButton.frame = CGRect(x: bounds.width - 72, y: 10, width: 62, height: 30)
        let fieldsW = bounds.width - 120
        if let shortcut = shortcutEditor {
            // [;shortcut][types out], the shortcut a third of the way.
            let w = min(112, floor(fieldsW * 0.36))
            shortcut.frame = CGRect(x: 40, y: 8, width: w, height: 34)
            editor.frame = CGRect(x: shortcut.frame.maxX + 6, y: 8, width: fieldsW - w - 6, height: 34)
        } else {
            editor.frame = CGRect(x: 40, y: 8, width: fieldsW, height: 34)
        }
        statusLabel.frame = CGRect(x: 12, y: 48, width: bounds.width - 24, height: 34)
    }
}
