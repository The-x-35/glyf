import UIKit

protocol NoteEditSurfaceDelegate: AnyObject {
    func noteEditActivated(_ editor: InlineEditor)
    func noteEditSaved()
    func noteEditClosed()
}

/// Notes, editable WITHOUT leaving the keyboard: a strip above the letter
/// keys (same pattern as emoji search) — type, Save, done. SecretScanner
/// still stands guard inside NotesStore.
final class NoteEditSurface: UIView {

    weak var delegate: NoteEditSurfaceDelegate?

    static let stripHeight: CGFloat = 96

    private let noteId: String?
    let editor = InlineEditor(placeholder: "Write a note…")
    private let closeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    init(noteId: String?, text: String) {
        self.noteId = noteId
        super.init(frame: .zero)
        backgroundColor = .clear

        editor.accessibilityIdentifier = "noteedit:field"
        if !text.isEmpty { editor.append(text) }
        let tap = UITapGestureRecognizer(target: self, action: #selector(fieldTapped))
        editor.addGestureRecognizer(tap)
        addSubview(editor)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.setPreferredSymbolConfiguration(.init(pointSize: 13, weight: .semibold),
                                                    forImageIn: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "noteedit:close"
        closeButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.noteEditClosed()
        }, for: .touchUpInside)
        addSubview(closeButton)

        saveButton.setTitle("Save", for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        saveButton.setTitleColor(Glass.surfaceCard, for: .normal)
        saveButton.backgroundColor = Glass.brandInk
        saveButton.layer.cornerRadius = 15
        saveButton.layer.cornerCurve = .continuous
        saveButton.accessibilityIdentifier = "noteedit:save"
        saveButton.addAction(UIAction { [weak self] _ in self?.save() }, for: .touchUpInside)
        addSubview(saveButton)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = Glass.accentDanger
        statusLabel.textAlignment = .center
        addSubview(statusLabel)

        MemoryLogger.logSurface("noteedit")
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func fieldTapped() {
        editor.isActive = true
        delegate?.noteEditActivated(editor)
    }

    private func save() {
        let text = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let refusal = NotesStore.shared.upsert(id: noteId, text: text) {
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
        editor.frame = CGRect(x: 40, y: 8, width: bounds.width - 120, height: 34)
        statusLabel.frame = CGRect(x: 12, y: 50, width: bounds.width - 24, height: 16)
    }
}
