import UIKit

protocol PotSurfaceDelegate: AnyObject {
    /// The pot's line, or the proposal's, put in the chat as is.
    func potInsert(_ text: String)
    /// A proposal to vote on, or the payout to file, in Trezu.
    func potOpen(_ url: String)
    /// The account's editor came or went: the keys follow.
    func potLayoutChanged()
}

/// The group pot over the keys (docs/NEAR-SPEC.md, Hand-off: the pot): a
/// look at a Sputnik DAO's treasury (GET /near/pot: its line, then the
/// proposals still taking votes, each with Vote), or a payout to propose
/// for the members' vote (GET /near/pot/propose-link), filed in Trezu,
/// where the person signs in with their own NEAR wallet. Nothing is signed
/// here; Insert puts the answer's words in the chat.
final class PotSurface: UIView {

    weak var delegate: PotSurfaceDelegate?

    private(set) var ask: PotAsk
    let dao: String

    /// The payee's NEAR account: what was typed when it is one, else asked
    /// for here ("caterer's NEAR account") and checked on NEAR.
    private var account: String?
    private var accountProblem: String?
    private var checking = false

    private var view: PotView?
    private var proposal: PotProposal?
    private var loading = true
    private var task: URLSessionDataTask?

    /// The strip over the keys while the account is typed.
    static let editStripHeight: CGFloat = 64
    private(set) var editing = false
    var editStripHeight: CGFloat? { editing ? Self.editStripHeight : nil }
    var activeEditor: InlineEditor? { editing ? editor : nil }

    // MARK: views

    private let card = UIView()
    private let headline = UILabel()
    private let detail = UILabel()
    private let warning = UILabel()
    private let accountRow = UIControl()
    private let accountName = UILabel()
    private let accountValue = UILabel()
    private let list = UIScrollView()
    private var rows: [UIView] = []
    private let primary = UIButton(type: .system)
    private let secondary = UIButton(type: .system)
    let editor = InlineEditor(placeholder: "name.near")
    private let editKey = UILabel()
    private let doneButton = UIButton(type: .system)

    init(ask: PotAsk, dao: String) {
        self.ask = ask
        self.dao = dao
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid
        if let to = ask.to, PotAsk.isNEARAccount(to) { account = to.lowercased() }
        build()
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    var headerIcon: String { SponsorMenu.Sponsor.near.screenId }
    var headerTitle: String { ask.pay ? "Pay from the pot" : "Group pot" }

    /// "caterer", from "the caterer".
    private var payeeWords: String {
        (ask.to ?? "").replacingOccurrences(of: #"^the\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    // MARK: build

    private func build() {
        card.backgroundColor = Glass.surfaceCard
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.accessibilityIdentifier = "pot:card"
        addSubview(card)
        headline.font = .systemFont(ofSize: 15, weight: .semibold)
        headline.textColor = Glass.textPrimary
        headline.numberOfLines = 3
        headline.lineBreakMode = .byWordWrapping
        headline.adjustsFontSizeToFitWidth = true
        headline.minimumScaleFactor = 0.75
        headline.accessibilityIdentifier = "pot:text"
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = Glass.textSecondary
        detail.numberOfLines = 2
        detail.lineBreakMode = .byWordWrapping
        detail.accessibilityIdentifier = "pot:fill"
        warning.font = .systemFont(ofSize: 13, weight: .medium)
        warning.textColor = .systemRed
        warning.numberOfLines = 2
        warning.lineBreakMode = .byWordWrapping
        warning.accessibilityIdentifier = "pot:warning"
        for l in [headline, detail, warning] { card.addSubview(l) }

        accountRow.backgroundColor = Glass.surfaceCard
        accountRow.layer.cornerRadius = 12
        accountRow.layer.cornerCurve = .continuous
        accountRow.accessibilityIdentifier = "pot:account"
        accountName.font = .systemFont(ofSize: 15)
        accountName.textColor = Glass.textSecondary
        accountName.adjustsFontSizeToFitWidth = true
        accountName.minimumScaleFactor = 0.75
        accountValue.font = .systemFont(ofSize: 15, weight: .semibold)
        accountValue.textColor = Glass.imBlue
        accountValue.textAlignment = .right
        accountValue.adjustsFontSizeToFitWidth = true
        accountValue.minimumScaleFactor = 0.7
        accountValue.lineBreakMode = .byClipping
        for v in [accountName, accountValue] { v.isUserInteractionEnabled = false; accountRow.addSubview(v) }
        accountRow.addAction(UIAction { [weak self] _ in self?.beginAccount() }, for: .touchUpInside)
        addSubview(accountRow)

        list.showsVerticalScrollIndicator = false
        list.alwaysBounceVertical = false
        list.accessibilityIdentifier = "pot:proposals"
        addSubview(list)

        for (b, blue) in [(primary, true), (secondary, false)] {
            b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.8
            b.layer.cornerRadius = 14
            b.layer.cornerCurve = .continuous
            b.backgroundColor = blue ? Glass.imBlue : Self.offFill
            b.setTitleColor(blue ? .white : Glass.textPrimary, for: .normal)
            addSubview(b)
        }
        primary.accessibilityIdentifier = "pot:go"
        secondary.accessibilityIdentifier = "pot:insert"
        primary.addAction(UIAction { [weak self] _ in self?.primaryTapped() }, for: .touchUpInside)
        secondary.addAction(UIAction { [weak self] _ in self?.insertTapped() }, for: .touchUpInside)

        editKey.font = .systemFont(ofSize: 12, weight: .semibold)
        editKey.textColor = Glass.textSecondary
        addSubview(editKey)
        editor.accessibilityIdentifier = "pot:editor"
        addSubview(editor)
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.backgroundColor = Glass.imBlue
        doneButton.layer.cornerRadius = 16
        doneButton.layer.cornerCurve = .continuous
        doneButton.accessibilityIdentifier = "pot:done"
        doneButton.addAction(UIAction { [weak self] _ in self?.endEditing() }, for: .touchUpInside)
        addSubview(doneButton)
    }

    private static let offFill = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 0, alpha: 0.06) }

    // MARK: asking

    private static func q(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: safe) ?? s
    }

    private static let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    private func load() {
        task?.cancel()
        loading = true
        render()
        if !ask.pay {
            task = BackendClient.shared.evmJSONResult(path: "/near/pot?dao=\(Self.q(dao))") { [weak self] ok, obj in
                guard let self else { return }
                self.loading = false
                self.view = PotView(ok: ok, obj)
                self.render()
            }
            return
        }
        // The payout waits for the account it pays.
        guard let account else { loading = false; render(); return }
        var path = "/near/pot/propose-link?dao=\(Self.q(dao))&to=\(Self.q(account))"
            + "&amount=\(Self.q(ask.amount ?? ""))&coin=\(Self.q(ask.coin))"
        if let note = ask.note { path += "&note=\(Self.q(note))" }
        task = BackendClient.shared.evmJSONResult(path: path) { [weak self] ok, obj in
            guard let self else { return }
            self.loading = false
            self.proposal = PotProposal(ok: ok, obj, to: account, account: SettingsStore.current.nearAccount)
            self.render()
        }
    }

    /// The typed account, checked on NEAR (GET /names/resolve) before the
    /// payout is asked for: "No NEAR account caterer.near".
    private func check(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard PotAsk.isNEARAccount(name) else {
            accountProblem = name.isEmpty ? nil : "Pay out to a NEAR account, like caterer.near"
            render()
            return
        }
        if name.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil {
            account = name
            accountProblem = nil
            load()
            return
        }
        checking = true
        accountProblem = nil
        render()
        task?.cancel()
        task = BackendClient.shared.evmJSONResult(path: "/names/resolve?name=\(Self.q(name))") { [weak self] ok, obj in
            guard let self else { return }
            self.checking = false
            if ok, obj?["exists"] as? Bool != false {
                self.account = name
                self.load()
            } else if (obj?["found"] as? Bool) == false || (obj?["exists"] as? Bool) == false {
                self.accountProblem = "No NEAR account \(name)"
                self.render()
            } else {
                self.accountProblem = "Couldn't check \(name) on NEAR"
                self.render()
            }
        }
    }

    // MARK: editing

    private func beginAccount() {
        editor.setText(account ?? "")
        editKey.text = "\(payeeWords)'s NEAR account"
        editing = true
        render()
        delegate?.potLayoutChanged()
    }

    /// Return or Done: the account is checked.
    func endEditing() {
        guard editing else { return }
        editing = false
        render()
        delegate?.potLayoutChanged()
        check(editor.text)
    }

    // MARK: taps

    private var insertText: String? { ask.pay ? proposal?.text : view?.text }

    private func primaryTapped() {
        if ask.pay {
            guard let url = proposal?.url, proposal?.notMember != true else {
                if account == nil { beginAccount() }
                return
            }
            delegate?.potOpen(url)
        } else if let text = view?.text {
            delegate?.potInsert(text)
        }
    }

    private func insertTapped() {
        if let text = insertText { delegate?.potInsert(text) }
    }

    @objc private func voteTapped(_ sender: UIButton) {
        guard let open = view?.open, sender.tag < open.count, let url = open[sender.tag].url else { return }
        delegate?.potOpen(url)
    }

    // MARK: render

    private func render() {
        let panel = !editing
        card.isHidden = !panel
        list.isHidden = !panel || ask.pay
        primary.isHidden = !panel
        secondary.isHidden = !panel || !ask.pay
        let needsAccount = ask.pay && (ask.to.map { !PotAsk.isNEARAccount($0) } ?? false)
        accountRow.isHidden = !panel || !needsAccount
        editKey.isHidden = panel
        editor.isHidden = panel
        doneButton.isHidden = panel

        accountName.text = "\(payeeWords)'s NEAR account"
        accountValue.text = checking ? "Checking…" : (account ?? "Add")
        warning.text = nil
        detail.text = nil
        if ask.pay { renderPay() } else { renderLook() }
        setNeedsLayout()
    }

    private func renderLook() {
        primary.setTitle("Insert", for: .normal)
        if loading { headline.text = "Reading the pot…"; setPrimary(on: false); fillRows([]); return }
        if let error = view?.error { headline.text = error; setPrimary(on: false); fillRows([]); return }
        headline.text = view?.text
        let open = view?.open ?? []
        detail.text = open.isEmpty ? "No proposals open" : nil
        setPrimary(on: view?.text != nil)
        fillRows(open)
    }

    private func renderPay() {
        primary.setTitle("Propose in Trezu", for: .normal)
        secondary.setTitle("Insert", for: .normal)
        let money = PotAsk.money(ask.amount ?? "", ask.coin)
        if account == nil {
            headline.text = "Propose \(money) to \(payeeWords) from the \(ask.potName)"
            warning.text = accountProblem
            setPrimary(on: false)
            setSecondary(on: false)
            return
        }
        if loading { headline.text = "Asking the pot…"; setPrimary(on: false); setSecondary(on: false); return }
        guard let p = proposal, p.error == nil else {
            headline.text = "Propose \(money) to \(account ?? "")"
            warning.text = proposal?.error
            setPrimary(on: false)
            setSecondary(on: false)
            return
        }
        headline.text = p.headline
        detail.text = p.fill
        if p.notMember { warning.text = PotProposal.membersOnly }
        setPrimary(on: p.url != nil && !p.notMember)
        setSecondary(on: p.text != nil)
    }

    private func setPrimary(on: Bool) {
        primary.isEnabled = on
        primary.backgroundColor = on ? Glass.imBlue : Self.offFill
        primary.setTitleColor(on ? .white : Glass.textSecondary, for: .normal)
    }

    private func setSecondary(on: Bool) {
        secondary.isEnabled = on
        secondary.setTitleColor(on ? Glass.textPrimary : Glass.textSecondary, for: .normal)
    }

    /// One row per open proposal: its line, and Vote (Trezu, where members vote).
    private func fillRows(_ open: [PotView.Proposal]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        for (k, p) in open.enumerated() {
            let row = UIView()
            row.backgroundColor = Glass.surfaceCard
            row.layer.cornerRadius = 12
            row.layer.cornerCurve = .continuous
            row.accessibilityIdentifier = "pot:proposal:\(p.id)"
            let line = UILabel()
            line.text = p.line
            line.font = .systemFont(ofSize: 14)
            line.textColor = Glass.textPrimary
            line.numberOfLines = 2
            line.lineBreakMode = .byWordWrapping
            line.adjustsFontSizeToFitWidth = true
            line.minimumScaleFactor = 0.75
            line.tag = 1
            row.addSubview(line)
            let vote = UIButton(type: .system)
            vote.setTitle("Vote", for: .normal)
            vote.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            vote.setTitleColor(Glass.imBlue, for: .normal)
            vote.backgroundColor = Glass.imBlue.withAlphaComponent(0.14)
            vote.layer.cornerRadius = 14
            vote.tag = k
            vote.isEnabled = p.url != nil
            vote.accessibilityIdentifier = "pot:vote:\(p.id)"
            vote.addTarget(self, action: #selector(voteTapped(_:)), for: .touchUpInside)
            row.addSubview(vote)
            list.addSubview(row)
            rows.append(row)
        }
    }

    // MARK: layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let x: CGFloat = 12, cw = w - 24
        if editing {
            let doneW: CGFloat = 72
            doneButton.frame = CGRect(x: w - 12 - doneW, y: 16, width: doneW, height: 32)
            editKey.frame = CGRect(x: 16, y: 4, width: doneButton.frame.minX - 24, height: 15)
            editor.frame = CGRect(x: 12, y: 21, width: doneButton.frame.minX - 22, height: 36)
            return
        }
        let goH: CGFloat = 42
        let goY = h - 8 - goH
        if secondary.isHidden {
            primary.frame = CGRect(x: x, y: goY, width: cw, height: goH)
        } else {
            let insertW: CGFloat = 96
            secondary.frame = CGRect(x: x + cw - insertW, y: goY, width: insertW, height: goH)
            primary.frame = CGRect(x: x, y: goY, width: cw - insertW - 8, height: goH)
        }
        // The card fits its words.
        let inner = cw - 28
        func height(_ l: UILabel) -> CGFloat {
            guard let t = l.text, !t.isEmpty else { return 0 }
            return ceil(l.sizeThatFits(CGSize(width: inner, height: 200)).height)
        }
        var y: CGFloat = 12
        let hh = min(height(headline), 64)
        headline.frame = CGRect(x: 14, y: y, width: inner, height: hh)
        y += hh
        for l in [detail, warning] {
            let lh = min(height(l), 34)
            l.frame = CGRect(x: 14, y: lh > 0 ? y + 4 : y, width: inner, height: lh)
            if lh > 0 { y += lh + 4 }
        }
        card.frame = CGRect(x: x, y: 8, width: cw, height: y + 12)
        var below = card.frame.maxY + 6
        if !accountRow.isHidden {
            accountRow.frame = CGRect(x: x, y: below, width: cw, height: 44)
            accountName.frame = CGRect(x: 14, y: 0, width: cw * 0.6 - 14, height: 44)
            accountValue.frame = CGRect(x: cw * 0.6, y: 0, width: cw * 0.4 - 14, height: 44)
            below = accountRow.frame.maxY + 6
        }
        list.frame = CGRect(x: 0, y: below, width: w, height: max(0, goY - 6 - below))
        var ry: CGFloat = 0
        for row in rows {
            row.frame = CGRect(x: x, y: ry, width: cw, height: 46)
            let voteW: CGFloat = 64
            for v in row.subviews {
                if let b = v as? UIButton { b.frame = CGRect(x: cw - 10 - voteW, y: 9, width: voteW, height: 28) }
                else { v.frame = CGRect(x: 12, y: 2, width: cw - voteW - 30, height: 42) }
            }
            ry += 46 + 4
        }
        list.contentSize = CGSize(width: w, height: ry)
    }
}
