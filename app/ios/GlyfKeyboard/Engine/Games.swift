import Foundation

/// The keyboard's two games as plain rules: Snake, and Chomp (a maze of
/// pellets and ghosts after the arcade classic; the name is ours). Both
/// move one cell a tick on a grid sized to the keyboard's panel, so the
/// views only draw and the tests can play them. Android's `Games.kt` is the
/// same rules, written twice: change one, change both.
enum Games {
    struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    enum Dir: CaseIterable {
        // The order ties are broken in, as in the arcade: up, left, down, right.
        case up, left, down, right
        var dx: Int { self == .left ? -1 : self == .right ? 1 : 0 }
        var dy: Int { self == .up ? -1 : self == .down ? 1 : 0 }
        var opposite: Dir {
            switch self {
            case .up: return .down
            case .down: return .up
            case .left: return .right
            case .right: return .left
            }
        }
    }

    /// A small seeded generator: the same numbers on both platforms for a
    /// seed, so a test can know where the food lands.
    struct Random {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next(_ n: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return n <= 1 ? 0 : Int((state >> 33) % UInt64(n))
        }
    }
}

// MARK: - Snake

final class SnakeGame {
    enum Event { case moved, ate, crashed, won }

    let cols: Int
    let rows: Int
    /// Head first.
    private(set) var body: [Games.Cell]
    private(set) var heading: Games.Dir = .right
    private(set) var food: Games.Cell
    private(set) var score = 0
    private(set) var over = false
    /// Swipes waiting for their step: two, so a quick up-then-left lands both.
    private var turns: [Games.Dir] = []
    private var random: Games.Random

    /// `body` (head first, heading right) is for tests; a game starts three
    /// long in the middle of the left side.
    init(cols: Int = 22, rows: Int = 11, seed: UInt64 = UInt64.random(in: 1...UInt64.max),
         body: [Games.Cell]? = nil) {
        self.cols = cols
        self.rows = rows
        random = Games.Random(seed: seed)
        let y = rows / 2
        self.body = body ?? [Games.Cell(x: 5, y: y), Games.Cell(x: 4, y: y), Games.Cell(x: 3, y: y)]
        food = self.body[0]
        food = placeFood()
    }

    /// Where the head goes next; never straight back into the body.
    func turn(_ d: Games.Dir) {
        let last = turns.last ?? heading
        guard d != last, d != last.opposite, turns.count < 2 else { return }
        turns.append(d)
    }

    /// The snake's pace: a step every 150ms, a little quicker every four
    /// bites, never quicker than 70ms.
    var interval: TimeInterval { max(0.07, 0.15 - Double(score / 4) * 0.01) }

    @discardableResult
    func step() -> Event {
        guard !over else { return .crashed }
        if !turns.isEmpty { heading = turns.removeFirst() }
        let head = body[0]
        // No walls: the board wraps, which is kinder on a keyboard-sized field.
        let next = Games.Cell(x: (head.x + heading.dx + cols) % cols, y: (head.y + heading.dy + rows) % rows)
        let eats = next == food
        // The tail moves out of the way this step, unless the snake grows.
        let blocking = eats ? body[...] : body.dropLast()
        if blocking.contains(next) {
            over = true
            return .crashed
        }
        body.insert(next, at: 0)
        guard eats else {
            body.removeLast()
            return .moved
        }
        score += 1
        if body.count == cols * rows {
            over = true
            return .won
        }
        food = placeFood()
        return .ate
    }

    private func placeFood() -> Games.Cell {
        let taken = Set(body)
        var k = random.next(cols * rows - body.count)
        for y in 0..<rows {
            for x in 0..<cols where !taken.contains(Games.Cell(x: x, y: y)) {
                if k == 0 { return Games.Cell(x: x, y: y) }
                k -= 1
            }
        }
        return body[0]
    }
}

// MARK: - Chomp

final class ChompGame {
    enum Event: Equatable { case pellet, power, ghost(Int), caught, cleared, over }

    enum GhostState: Equatable {
        /// In the pen; leaves after this many more ticks.
        case home(Int)
        /// On its way out through the door.
        case leaving
        case roaming
    }

    struct Ghost {
        let id: Int
        var at: Games.Cell
        /// Where it was a tick ago, so the view can slide it across.
        var from: Games.Cell
        var dir: Games.Dir = .up
        var state: GhostState
        /// Blue and running: a power pellet was eaten while it was out.
        var scared = false
    }

    /// 21 by 11, wide and short like the keyboard. # wall, . pellet,
    /// o power pellet, - the pen's door, G the pen, P where Chomp starts.
    /// The middle row runs off both edges and comes back on the other side.
    static let map = [
        "#####################",
        "#o........#........o#",
        "#.###.###.#.###.###.#",
        "#...................#",
        "#.###.#.##-##.#.###.#",
        "......#.#GGG#.#......",
        "#.###.#.#####.#.###.#",
        "#.........P.........#",
        "#.###.###.#.###.###.#",
        "#o........#........o#",
        "#####################",
    ]

    let cols = 21
    let rows = 11
    let walls: Set<Games.Cell>
    let door: Games.Cell
    let pen: [Games.Cell]
    let start: Games.Cell
    /// The first cell outside the door.
    var exit: Games.Cell { Games.Cell(x: door.x, y: door.y - 1) }

    private(set) var pellets: Set<Games.Cell> = []
    private(set) var powers: Set<Games.Cell> = []
    private(set) var player: Games.Cell
    private(set) var playerFrom: Games.Cell
    private(set) var heading: Games.Dir = .left
    /// The last swipe, kept until the maze lets Chomp take it.
    var wanted: Games.Dir?
    private(set) var ghosts: [Ghost] = []
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var level = 1
    /// Ticks left of the power pellet's fright.
    private(set) var frightened = 0
    /// Ticks everything holds still after a catch or a cleared maze.
    private(set) var pause = 0
    private(set) var over = false
    private(set) var tick = 0
    private var combo = 0
    private var random: Games.Random

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        random = Games.Random(seed: seed)
        var walls = Set<Games.Cell>(), pen: [Games.Cell] = []
        var door = Games.Cell(x: 10, y: 4), start = Games.Cell(x: 10, y: 7)
        for (y, row) in Self.map.enumerated() {
            for (x, ch) in row.enumerated() {
                let c = Games.Cell(x: x, y: y)
                switch ch {
                case "#": walls.insert(c)
                case "-": door = c
                case "G": pen.append(c)
                case "P": start = c
                default: break
                }
            }
        }
        self.walls = walls
        self.door = door
        self.pen = pen
        self.start = start
        player = start
        playerFrom = start
        fillMaze()
        placeActors()
    }

    /// A step every 140ms on the first maze, quicker on each one after.
    var interval: TimeInterval { max(0.11, 0.14 - Double(level - 1) * 0.01) }
    private var frightTicks: Int { max(20, 45 - (level - 1) * 5) }

    func next(_ c: Games.Cell, _ d: Games.Dir) -> Games.Cell {
        Games.Cell(x: (c.x + d.dx + cols) % cols, y: min(max(c.y + d.dy, 0), rows - 1))
    }

    /// Chomp and roaming ghosts keep to the corridors: not a wall, not the pen.
    func open(_ c: Games.Cell) -> Bool {
        !walls.contains(c) && c != door && !pen.contains(c)
    }

    @discardableResult
    func step() -> [Event] {
        guard !over else { return [] }
        tick += 1
        playerFrom = player
        for i in ghosts.indices { ghosts[i].from = ghosts[i].at }
        if pause > 0 {
            pause -= 1
            return []
        }
        var events: [Event] = []

        // Chomp: turn when the maze allows the last swipe, then run on.
        if let w = wanted, open(next(player, w)) {
            heading = w
            wanted = nil
        }
        let ahead = next(player, heading)
        if open(ahead) { player = ahead }
        if pellets.remove(player) != nil {
            score += 10
            events.append(.pellet)
        }
        if powers.remove(player) != nil {
            score += 50
            frightened = frightTicks
            combo = 0
            // Every ghost that is out turns tail; the ones in the pen don't care.
            for i in ghosts.indices {
                if case .home = ghosts[i].state { continue }
                ghosts[i].scared = true
                if ghosts[i].state == .roaming { ghosts[i].dir = ghosts[i].dir.opposite }
            }
            events.append(.power)
        }
        if collide(&events) { return events }

        for i in ghosts.indices { moveGhost(i) }
        if frightened > 0 {
            frightened -= 1
            if frightened == 0 {
                combo = 0
                for i in ghosts.indices { ghosts[i].scared = false }
            }
        }
        if collide(&events) { return events }

        if pellets.isEmpty && powers.isEmpty {
            level += 1
            fillMaze()
            placeActors()
            pause = 12
            events.append(.cleared)
        }
        return events
    }

    // MARK: Ghosts

    private func moveGhost(_ i: Int) {
        var g = ghosts[i]
        switch g.state {
        case .home(let wait):
            g.state = wait > 0 ? .home(wait - 1) : .leaving
        case .leaving:
            // Along the pen to the door's column, then up and out.
            if g.at.x != door.x {
                g.dir = g.at.x < door.x ? .right : .left
            } else {
                g.dir = .up
            }
            g.at = Games.Cell(x: g.at.x + g.dir.dx, y: g.at.y + g.dir.dy)
            if g.at == exit {
                g.state = .roaming
                g.dir = random.next(2) == 0 ? .left : .right
            }
        case .roaming:
            // Scared ghosts go at half pace; the rest skip one tick in five
            // on the first maze, one in ten from the third.
            let skip = g.scared ? tick % 2 == 0 : tick % (level >= 3 ? 10 : 5) == 0
            guard !skip else { break }
            var options = Games.Dir.allCases.filter { $0 != g.dir.opposite && open(next(g.at, $0)) }
            if options.isEmpty { options = [g.dir.opposite] }
            let dir: Games.Dir
            if g.scared || (options.count > 1 && random.next(level >= 3 ? 10 : 6) == 0) {
                dir = options[random.next(options.count)]
            } else {
                let t = target(for: g)
                dir = options.min { distance(next(g.at, $0), t) < distance(next(g.at, $1), t) }!
            }
            g.dir = dir
            g.at = next(g.at, dir)
        }
        ghosts[i] = g
    }

    /// Where each one heads: the first straight at Chomp, the second a few
    /// cells ahead of it, the third at it from afar and to its corner up close.
    private func target(for g: Ghost) -> Games.Cell {
        switch g.id {
        case 0:
            return player
        case 1:
            return Games.Cell(x: player.x + heading.dx * 3, y: player.y + heading.dy * 3)
        default:
            return distance(g.at, player) > 25 ? player : Games.Cell(x: 0, y: rows - 1)
        }
    }

    private func distance(_ a: Games.Cell, _ b: Games.Cell) -> Int {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }

    /// A ghost and Chomp on one cell, or passing through each other. True
    /// when Chomp was caught (the rest of the tick is off).
    private func collide(_ events: inout [Event]) -> Bool {
        for i in ghosts.indices where ghosts[i].state == .roaming {
            let g = ghosts[i]
            let met = g.at == player || (g.at == playerFrom && g.from == player)
            guard met else { continue }
            if g.scared {
                let points = 200 << min(combo, 3)
                combo += 1
                score += points
                ghosts[i] = Ghost(id: g.id, at: pen[g.id % pen.count], from: pen[g.id % pen.count],
                                  state: .home(15))
                events.append(.ghost(points))
                continue
            }
            lives -= 1
            events.append(.caught)
            if lives == 0 {
                over = true
                events.append(.over)
            } else {
                placeActors()
                pause = 10
            }
            return true
        }
        return false
    }

    /// For tests: Chomp at `player`, the first ghost out in the maze at
    /// `ghost` (the others kept in the pen), and optionally only `pellets`
    /// left to eat.
    func stage(player p: Games.Cell, heading h: Games.Dir, ghost: Games.Cell? = nil,
               ghostDir: Games.Dir = .left, pellets left: Set<Games.Cell>? = nil) {
        player = p
        playerFrom = p
        heading = h
        wanted = nil
        pause = 0
        if let ghost {
            ghosts[0].at = ghost
            ghosts[0].from = ghost
            ghosts[0].dir = ghostDir
            ghosts[0].state = .roaming
        }
        for i in ghosts.indices.dropFirst() { ghosts[i].state = .home(1000) }
        if let left {
            pellets = left
            powers = []
        }
    }

    // MARK: Setting up

    private func fillMaze() {
        pellets = []
        powers = []
        for (y, row) in Self.map.enumerated() {
            for (x, ch) in row.enumerated() {
                if ch == "." { pellets.insert(Games.Cell(x: x, y: y)) }
                if ch == "o" { powers.insert(Games.Cell(x: x, y: y)) }
            }
        }
    }

    private func placeActors() {
        player = start
        playerFrom = start
        heading = .left
        wanted = nil
        frightened = 0
        combo = 0
        ghosts = pen.enumerated().map { i, c in
            Ghost(id: i, at: c, from: c, state: .home(i * 12))
        }
    }
}
