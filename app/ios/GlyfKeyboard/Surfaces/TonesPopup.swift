import UIKit

protocol TonesPopupDelegate: AnyObject {
    func tonesPicked(_ tone: String)
    func tonesClosed()
}

/// §6.13 `R` ★ — Humanize: a compact tone picker over the key grid. One tap
/// runs `rewrite.tone` on the draft with the chosen tone; the result lands in
/// the Glyf Bar's normal preview strip (Replace / Insert / Copy — §6.4).
final class TonesPopup: UIView {

    weak var delegate: TonesPopupDelegate?

    /// (label, tone var value) — the value is prose the prompt embeds.
    private static let tones: [(String, String)] = [
        ("Natural", "natural, human"),
        ("Professional", "professional"),
        ("Casual", "casual"),
        ("Gen-Z", "gen-z playful"),
    ]

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.surfaceCard.withAlphaComponent(0.97)
        accessibilityIdentifier = "tones:popup"

        let title = UILabel()
        title.text = "Rewrite your draft as…"
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = Glass.textPrimary
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = Glass.textSecondary
        close.accessibilityIdentifier = "tones:close"
        close.addAction(UIAction { [weak self] _ in self?.delegate?.tonesClosed() },
                        for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        addSubview(close)

        func pill(_ label: String, _ value: String) -> UIButton {
            let b = UIButton(type: .system)
            b.setTitle(label, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            b.setTitleColor(Glass.textPrimary, for: .normal)
            b.backgroundColor = Glass.fillKey
            b.layer.cornerRadius = 12
            b.layer.cornerCurve = .continuous
            b.layer.borderWidth = Glass.hairlineWidth
            b.layer.borderColor = Glass.strokeHairline.cgColor
            b.layer.shadowOpacity = Glass.keyShadowOpacity
            b.layer.shadowOffset = Glass.keyShadowOffset
            b.layer.shadowRadius = Glass.keyShadowRadius
            b.accessibilityIdentifier = "tones:\(label.lowercased())"
            b.addAction(UIAction { [weak self] _ in self?.delegate?.tonesPicked(value) },
                        for: .touchUpInside)
            return b
        }
        let row1 = UIStackView(arrangedSubviews: [pill(Self.tones[0].0, Self.tones[0].1),
                                                  pill(Self.tones[1].0, Self.tones[1].1)])
        let row2 = UIStackView(arrangedSubviews: [pill(Self.tones[2].0, Self.tones[2].1),
                                                  pill(Self.tones[3].0, Self.tones[3].1)])
        let grid = UIStackView(arrangedSubviews: [row1, row2])
        for row in [row1, row2] {
            row.axis = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually
        }
        grid.axis = .vertical
        grid.spacing = 10
        grid.distribution = .fillEqually
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            close.widthAnchor.constraint(equalToConstant: 34),
            grid.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
