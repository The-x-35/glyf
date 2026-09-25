import UIKit

/// g menu → Games: Snake and Chomp in the keyboard's panel. A picker first,
/// then the game over the whole panel: swipe to steer, tap to pause. Best
/// scores stay on this phone. The rules live in Engine/Games.swift.
final class GamesSurface: UIView {

    enum Game: String { case snake, chomp }

    private let picker = UIStackView()
    private var cards: [Game: GameCard] = [:]
    private let bar = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let scoreLabel = UILabel()
    private let livesLabel = UILabel()
    private var board: GameBoardView?

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid

        picker.axis = .horizontal
        picker.distribution = .fillEqually
        picker.spacing = 10
        for game in [Game.snake, .chomp] {
            let card = GameCard(game: game)
            card.addAction(UIAction { [weak self] _ in self?.play(game) }, for: .touchUpInside)
            cards[game] = card
            picker.addArrangedSubview(card)
        }
        addSubview(picker)

        backButton.setImage(UIImage(systemName: "chevron.left",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)),
                            for: .normal)
        backButton.tintColor = Glass.textPrimary
        backButton.accessibilityIdentifier = "games:back"
        backButton.accessibilityLabel = "All games"
        backButton.addAction(UIAction { [weak self] _ in self?.showPicker() }, for: .touchUpInside)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Glass.textPrimary
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        scoreLabel.textColor = Glass.textSecondary
        scoreLabel.textAlignment = .right
        scoreLabel.accessibilityIdentifier = "games:score"
        livesLabel.font = .systemFont(ofSize: 12)
        livesLabel.textAlignment = .right
        for v in [backButton, titleLabel, scoreLabel, livesLabel] { bar.addSubview(v) }
        addSubview(bar)
        showPicker()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The panel is going away: stop the clock.
    func stop() { board?.stop() }

    private func showPicker() {
        board?.stop()
        board?.removeFromSuperview()
        board = nil
        for (game, card) in cards { card.best = Self.best(game) }
        picker.isHidden = false
        bar.isHidden = true
        setNeedsLayout()
    }

    private func play(_ game: Game) {
        picker.isHidden = true
        bar.isHidden = false
        titleLabel.text = game == .snake ? "Snake" : "Chomp"
        let b = GameBoardView(game: game)
        b.onChange = { [weak self] in self?.refreshBar() }
        insertSubview(b, belowSubview: bar)
        board = b
        refreshBar()
        setNeedsLayout()
    }

    private func refreshBar() {
        guard let board else { return }
        let best = Self.best(board.game)
        scoreLabel.text = best > 0 ? "\(board.score)  ·  Best \(max(best, board.score))" : "\(board.score)"
        scoreLabel.accessibilityValue = "Score \(board.score)"
        livesLabel.attributedText = board.lives.map {
            NSAttributedString(string: String(repeating: "●", count: max(0, $0)),
                               attributes: [.kern: 3, .foregroundColor: GameBoardView.chompYellow])
        }
        setNeedsLayout()
    }

    // MARK: Best scores (this phone only)

    static func best(_ game: Game) -> Int {
        UserDefaults.standard.integer(forKey: "games.best.\(game.rawValue)")
    }

    static func record(_ score: Int, for game: Game) {
        guard score > best(game) else { return }
        UserDefaults.standard.set(score, forKey: "games.best.\(game.rawValue)")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        picker.frame = bounds.insetBy(dx: 12, dy: 12)
        let barH: CGFloat = 30
        bar.frame = CGRect(x: 0, y: 0, width: w, height: barH)
        backButton.frame = CGRect(x: 4, y: 0, width: 36, height: barH)
        titleLabel.frame = CGRect(x: 38, y: 0, width: 120, height: barH)
        scoreLabel.frame = CGRect(x: w - 172, y: 0, width: 160, height: barH)
        let scoreW = scoreLabel.sizeThatFits(CGSize(width: 160, height: barH)).width
        livesLabel.frame = CGRect(x: w - 12 - scoreW - 14 - 48, y: 0, width: 48, height: barH)
        board?.frame = CGRect(x: 0, y: barH, width: w, height: max(0, h - barH))
    }
}

// MARK: - A game on the picker

private final class GameCard: UIControl {
    let game: GamesSurface.Game
    private let art = UIImageView()
    private let name = UILabel()
    private let bestLabel = UILabel()

    var best = 0 {
        didSet { bestLabel.text = best > 0 ? "Best \(best)" : "New" }
    }

    init(game: GamesSurface.Game) {
        self.game = game
        super.init(frame: .zero)
        backgroundColor = Glass.surfaceCard
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = Glass.hairlineWidth
        layer.borderColor = Glass.strokeHairline.cgColor
        accessibilityIdentifier = "games:\(game.rawValue)"
        accessibilityLabel = game == .snake ? "Snake" : "Chomp"
        isAccessibilityElement = true
        accessibilityTraits = .button
        art.image = GameBoardView.preview(game, size: CGSize(width: 96, height: 52))
        art.contentMode = .center
        name.text = game == .snake ? "Snake" : "Chomp"
        name.font = .systemFont(ofSize: 17, weight: .semibold)
        name.textColor = Glass.textPrimary
        name.textAlignment = .center
        bestLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        bestLabel.textColor = Glass.textSecondary
        bestLabel.textAlignment = .center
        for v in [art, name, bestLabel] {
            v.isUserInteractionEnabled = false
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let block: CGFloat = 52 + 10 + 22 + 18
        let top = (h - block) / 2
        art.frame = CGRect(x: 0, y: top, width: w, height: 52)
        name.frame = CGRect(x: 0, y: top + 62, width: w, height: 22)
        bestLabel.frame = CGRect(x: 0, y: top + 84, width: w, height: 18)
    }
}

// MARK: - The board

/// Draws either game, runs its clock and reads the swipes. Positions slide
/// between cells over each tick, so a 140ms step still moves smoothly.
final class GameBoardView: UIView {

    static let chompYellow = UIColor(red: 1, green: 0.78, blue: 0.24, alpha: 1)
    private static let ghostColors = [
        UIColor(red: 1, green: 0.35, blue: 0.37, alpha: 1),
        UIColor(red: 0.24, green: 0.78, blue: 0.94, alpha: 1),
        UIColor(red: 1, green: 0.62, blue: 0.26, alpha: 1),
    ]
    private static let scaredColor = UIColor(red: 0.28, green: 0.34, blue: 1, alpha: 1)
    private static let foodColor = UIColor(red: 1, green: 0.35, blue: 0.37, alpha: 1)
    private static let leafColor = UIColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)

    enum Phase { case ready, playing, paused, over }

    let game: GamesSurface.Game
    private var snake: SnakeGame?
    private var chomp: ChompGame?
    private(set) var phase: Phase = .ready {
        didSet { onChange?() }
    }
    var onChange: (() -> Void)?

    var score: Int { snake?.score ?? chomp?.score ?? 0 }
    var lives: Int? { chomp?.lives }

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var carry: CFTimeInterval = 0
    private var clock: CFTimeInterval = 0
    private var anchor: CGPoint?
    private let hint = UILabel()

    init(game: GamesSurface.Game) {
        self.game = game
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        accessibilityIdentifier = "games:board"
        isAccessibilityElement = true
        accessibilityLabel = game == .snake ? "Snake" : "Chomp"
        hint.font = .systemFont(ofSize: 15, weight: .semibold)
        hint.textColor = Glass.textPrimary
        hint.textAlignment = .center
        hint.backgroundColor = Glass.surfaceCard.withAlphaComponent(0.94)
        hint.layer.cornerRadius = 14
        hint.layer.cornerCurve = .continuous
        hint.clipsToBounds = true
        hint.isUserInteractionEnabled = false
        addSubview(hint)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        newGame()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func newGame() {
        if game == .snake { snake = SnakeGame() } else { chomp = ChompGame() }
        carry = 0
        phase = .ready
        showHint()
        setNeedsDisplay()
    }

    // MARK: Clock

    private func start() {
        guard link == nil else { return }
        last = CACurrentMediaTime()
        let l = CADisplayLink(target: WeakTick(self), selector: #selector(WeakTick.tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
        if phase == .playing { phase = .paused; showHint() }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { stop() }
    }

    fileprivate func tick(_ now: CFTimeInterval) {
        let dt = min(now - last, 0.25)
        last = now
        clock += dt
        guard phase == .playing else { setNeedsDisplay(); return }
        carry += dt
        var interval = snake?.interval ?? chomp?.interval ?? 0.14
        while carry >= interval {
            carry -= interval
            if let snake {
                let event = snake.step()
                if event == .ate { onChange?() }
                if snake.over { finish(); break }
            } else if let chomp {
                let events = chomp.step()
                if !events.isEmpty { onChange?() }
                if chomp.over { finish(); break }
            }
            interval = snake?.interval ?? chomp?.interval ?? 0.14
        }
        updateAccessibility()
        setNeedsDisplay()
    }

    private func finish() {
        GamesSurface.record(score, for: game)
        phase = .over
        link?.invalidate()
        link = nil
        showHint()
        setNeedsDisplay()
    }

    // MARK: Input

    @objc private func tapped() {
        switch phase {
        case .ready, .paused:
            phase = .playing
            showHint()
            start()
        case .playing:
            stop()
        case .over:
            newGame()
        }
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: self)
        switch g.state {
        case .began:
            anchor = p
        case .changed:
            guard let a = anchor else { return }
            let dx = p.x - a.x, dy = p.y - a.y
            // One turn per 14pt of travel, so a single drag can take a corner
            // and then another.
            guard max(abs(dx), abs(dy)) > 14 else { return }
            let dir: Games.Dir = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
            anchor = p
            steer(dir)
        default:
            anchor = nil
        }
    }

    private func steer(_ dir: Games.Dir) {
        if phase == .over { return }
        snake?.turn(dir)
        chomp?.wanted = dir
        if phase != .playing {
            phase = .playing
            showHint()
            start()
        }
    }

    private func showHint() {
        switch phase {
        case .ready: hint.text = "Swipe to start"
        case .paused: hint.text = "Paused. Tap to go on"
        case .over: hint.text = "Game over. Tap to play again"
        case .playing: hint.text = nil
        }
        hint.isHidden = hint.text == nil
        updateAccessibility()
        setNeedsLayout()
    }

    private func updateAccessibility() {
        let phaseName: String
        switch phase {
        case .ready: phaseName = "ready"
        case .playing: phaseName = "playing"
        case .paused: phaseName = "paused"
        case .over: phaseName = "over"
        }
        var parts = [phaseName, "score \(score)"]
        if let snake { parts.append("heading \(snake.heading)"); parts.append("length \(snake.body.count)") }
        if let chomp { parts.append("lives \(chomp.lives)"); parts.append("level \(chomp.level)") }
        accessibilityValue = parts.joined(separator: ", ")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = hint.sizeThatFits(CGSize(width: bounds.width - 40, height: 28))
        let w = min(bounds.width - 40, size.width + 32)
        hint.frame = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - 30) / 2, width: w, height: 30)
    }

    // MARK: Drawing

    /// The grid's cell size and where the board starts, centred.
    private func grid(cols: Int, rows: Int) -> (cell: CGFloat, origin: CGPoint) {
        let inset: CGFloat = 8
        let cell = floor(min((bounds.width - inset * 2) / CGFloat(cols),
                             (bounds.height - inset * 2) / CGFloat(rows)))
        return (cell, CGPoint(x: (bounds.width - cell * CGFloat(cols)) / 2,
                              y: (bounds.height - cell * CGFloat(rows)) / 2))
    }

    override func draw(_ rect: CGRect) {
        let progress = CGFloat(min(1, carry / (snake?.interval ?? chomp?.interval ?? 0.14)))
        if let snake { drawSnake(snake) }
        if let chomp { drawChomp(chomp, progress: phase == .playing ? progress : 1) }
    }

    private func drawSnake(_ s: SnakeGame) {
        let (cell, o) = grid(cols: s.cols, rows: s.rows)
        let field = CGRect(x: o.x, y: o.y, width: cell * CGFloat(s.cols), height: cell * CGFloat(s.rows))
        Glass.textPrimary.withAlphaComponent(0.05).setFill()
        UIBezierPath(roundedRect: field.insetBy(dx: -3, dy: -3), cornerRadius: 10).fill()
        func box(_ c: Games.Cell) -> CGRect {
            CGRect(x: o.x + CGFloat(c.x) * cell, y: o.y + CGFloat(c.y) * cell, width: cell, height: cell)
        }
        // The apple: red, with a leaf.
        let f = box(s.food)
        Self.foodColor.setFill()
        UIBezierPath(ovalIn: f.insetBy(dx: cell * 0.16, dy: cell * 0.16)).fill()
        Self.leafColor.setFill()
        UIBezierPath(ovalIn: CGRect(x: f.midX, y: f.minY + cell * 0.04, width: cell * 0.28, height: cell * 0.18)).fill()
        // One body, not a row of beads: a round-capped line through the
        // cells, lightening towards the tail. The shades are mixed opaque so
        // the joints don't darken where two pieces overlap. It breaks where
        // the snake runs off one edge and on at the other.
        let n = s.body.count
        func shade(_ i: Int) -> UIColor {
            let t = 0.45 * CGFloat(i) / CGFloat(max(n - 1, 1))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            Glass.accentPrimary.getRed(&r, green: &g, blue: &b, alpha: &a)
            return UIColor(red: r + (1 - r) * t, green: g + (1 - g) * t, blue: b + (1 - b) * t, alpha: 1)
        }
        for i in stride(from: n - 2, through: 0, by: -1) {
            let a = s.body[i], b = s.body[i + 1]
            guard abs(a.x - b.x) + abs(a.y - b.y) == 1 else { continue }
            let piece = UIBezierPath()
            piece.move(to: CGPoint(x: box(b).midX, y: box(b).midY))
            piece.addLine(to: CGPoint(x: box(a).midX, y: box(a).midY))
            piece.lineWidth = cell * 0.7
            piece.lineCapStyle = .round
            shade(i + 1).setStroke()
            piece.stroke()
        }
        Glass.accentPrimary.setFill()
        UIBezierPath(ovalIn: box(s.body[0]).insetBy(dx: cell * 0.08, dy: cell * 0.08)).fill()
        // Eyes on the head, looking where it goes.
        let head = box(s.body[0])
        let d = s.heading
        let side = CGPoint(x: CGFloat(-d.dy), y: CGFloat(d.dx))
        UIColor.white.setFill()
        for k in [-1, 1] as [CGFloat] {
            let c = CGPoint(x: head.midX + CGFloat(d.dx) * cell * 0.16 + side.x * k * cell * 0.2,
                            y: head.midY + CGFloat(d.dy) * cell * 0.16 + side.y * k * cell * 0.2)
            UIBezierPath(ovalIn: CGRect(x: c.x - cell * 0.1, y: c.y - cell * 0.1, width: cell * 0.2, height: cell * 0.2)).fill()
        }
    }

    private func drawChomp(_ g: ChompGame, progress: CGFloat) {
        let (cell, o) = grid(cols: g.cols, rows: g.rows)
        func centre(_ c: Games.Cell) -> CGPoint {
            CGPoint(x: o.x + (CGFloat(c.x) + 0.5) * cell, y: o.y + (CGFloat(c.y) + 0.5) * cell)
        }
        func slide(_ from: Games.Cell, _ to: Games.Cell) -> CGPoint {
            let a = centre(from), b = centre(to)
            // Through the side tunnel: no slide across the whole maze.
            if abs(from.x - to.x) > 1 { return b }
            return CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
        }
        // Walls: rounded tubes joining neighbouring wall cells.
        let tubes = UIBezierPath()
        for w in g.walls {
            let c = centre(w)
            tubes.move(to: c)
            tubes.addLine(to: c)
            for n in [Games.Cell(x: w.x + 1, y: w.y), Games.Cell(x: w.x, y: w.y + 1)] where g.walls.contains(n) {
                tubes.move(to: c)
                tubes.addLine(to: centre(n))
            }
        }
        tubes.lineWidth = cell * 0.34
        tubes.lineCapStyle = .round
        tubes.lineJoinStyle = .round
        Glass.accentPrimary.withAlphaComponent(0.8).setStroke()
        tubes.stroke()
        // The pen's door.
        let door = centre(g.door)
        let doorLine = UIBezierPath()
        doorLine.move(to: CGPoint(x: door.x - cell * 0.5, y: door.y))
        doorLine.addLine(to: CGPoint(x: door.x + cell * 0.5, y: door.y))
        doorLine.lineWidth = cell * 0.12
        UIColor(red: 1, green: 0.72, blue: 0.87, alpha: 1).setStroke()
        doorLine.stroke()
        // Pellets, and the four that bite back, pulsing.
        Glass.textPrimary.withAlphaComponent(0.55).setFill()
        for p in g.pellets {
            let c = centre(p), r = cell * 0.1
            UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        }
        let pulse = 0.75 + 0.25 * sin(CGFloat(clock) * 6)
        Glass.textPrimary.withAlphaComponent(0.85).setFill()
        for p in g.powers {
            let c = centre(p), r = cell * 0.24 * pulse
            UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        }
        // Ghosts.
        for ghost in g.ghosts {
            let c = slide(ghost.from, ghost.at)
            let blink = g.frightened < 12 && Int(clock * 6) % 2 == 0
            let body = ghost.scared ? (blink ? UIColor.white : Self.scaredColor)
                : Self.ghostColors[ghost.id % Self.ghostColors.count]
            Self.drawGhost(at: c, r: cell * 0.44, color: body, looking: ghost.dir, scared: ghost.scared)
        }
        // Chomp: the mouth works while it moves.
        let me = slide(g.playerFrom, g.player)
        let moving = phase == .playing && g.playerFrom != g.player
        let mouth = moving ? (0.5 + 0.5 * sin(CGFloat(clock) * 22)) * 0.9 : 0.55
        let facing: CGFloat
        switch g.heading {
        case .right: facing = 0
        case .down: facing = .pi / 2
        case .left: facing = .pi
        case .up: facing = -.pi / 2
        }
        let chompPath = UIBezierPath()
        chompPath.move(to: me)
        chompPath.addArc(withCenter: me, radius: cell * 0.46, startAngle: facing + mouth / 2,
                         endAngle: facing + 2 * .pi - mouth / 2, clockwise: true)
        chompPath.close()
        Self.chompYellow.setFill()
        chompPath.fill()
    }

    private static func drawGhost(at c: CGPoint, r: CGFloat, color: UIColor, looking d: Games.Dir, scared: Bool) {
        let path = UIBezierPath()
        let bottom = c.y + r * 0.92
        path.move(to: CGPoint(x: c.x - r, y: bottom))
        path.addLine(to: CGPoint(x: c.x - r, y: c.y))
        path.addArc(withCenter: c, radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: c.x + r, y: bottom))
        // Three little feet along the hem.
        let step = r * 2 / 6
        for k in 0..<6 {
            let x = c.x + r - step * CGFloat(k + 1)
            path.addLine(to: CGPoint(x: x, y: k % 2 == 0 ? bottom - r * 0.28 : bottom))
        }
        path.close()
        color.setFill()
        path.fill()
        if scared {
            UIColor.white.setFill()
            for k in [-1, 1] as [CGFloat] {
                let e = CGPoint(x: c.x + k * r * 0.34, y: c.y - r * 0.08)
                UIBezierPath(ovalIn: CGRect(x: e.x - r * 0.12, y: e.y - r * 0.12, width: r * 0.24, height: r * 0.24)).fill()
            }
            return
        }
        for k in [-1, 1] as [CGFloat] {
            let e = CGPoint(x: c.x + k * r * 0.36, y: c.y - r * 0.12)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: e.x - r * 0.26, y: e.y - r * 0.3, width: r * 0.52, height: r * 0.6)).fill()
            let p = CGPoint(x: e.x + CGFloat(d.dx) * r * 0.12, y: e.y + CGFloat(d.dy) * r * 0.14)
            UIColor(red: 0.12, green: 0.14, blue: 0.4, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: p.x - r * 0.13, y: p.y - r * 0.13, width: r * 0.26, height: r * 0.26)).fill()
        }
    }

    /// The picker's little picture of each game.
    static func preview(_ game: GamesSurface.Game, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            let cell: CGFloat = 12
            if game == .snake {
                let cells = [(1, 3), (2, 3), (3, 3), (3, 2), (4, 2), (5, 2)]
                for (i, c) in cells.enumerated() {
                    let alpha = 0.55 + 0.45 * CGFloat(i) / CGFloat(cells.count - 1)
                    Glass.accentPrimary.withAlphaComponent(alpha).setFill()
                    UIBezierPath(roundedRect: CGRect(x: CGFloat(c.0) * cell, y: CGFloat(c.1) * cell - 8,
                                                     width: cell - 2, height: cell - 2), cornerRadius: 3.5).fill()
                }
                foodColor.setFill()
                UIBezierPath(ovalIn: CGRect(x: 7 * cell, y: 2 * cell - 7, width: cell - 3, height: cell - 3)).fill()
            } else {
                let mid = size.height / 2
                Glass.textPrimary.withAlphaComponent(0.55).setFill()
                for k in 0..<3 {
                    UIBezierPath(ovalIn: CGRect(x: 34 + CGFloat(k) * 11, y: mid - 2, width: 4, height: 4)).fill()
                }
                let me = CGPoint(x: 18, y: mid)
                let p = UIBezierPath()
                p.move(to: me)
                p.addArc(withCenter: me, radius: 13, startAngle: 0.4, endAngle: 2 * .pi - 0.4, clockwise: true)
                p.close()
                chompYellow.setFill()
                p.fill()
                drawGhost(at: CGPoint(x: 78, y: mid), r: 12, color: ghostColors[0], looking: .left, scared: false)
            }
        }
    }
}

/// CADisplayLink holds its target strongly; this keeps the board free to go.
private final class WeakTick {
    weak var board: GameBoardView?
    init(_ board: GameBoardView) { self.board = board }
    @objc func tick(_ link: CADisplayLink) {
        guard let board else { return link.invalidate() }
        board.tick(link.timestamp)
    }
}
