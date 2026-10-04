import Foundation

/// The QWERTY letter grid in key widths (shared/typing/FORMAT.md "Scoring"):
/// row `r`, column `k` → center `(k + 0.5 + offset[r], (r + 0.5) · rowPitch)`.
struct KeyGeometry {
    static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    static let offsets: [Float] = [0, 0.5, 1.5]

    let rowPitch: Float
    private var xs = [Float](repeating: .nan, count: 26)
    private var ys = [Float](repeating: .nan, count: 26)

    init(rowPitch: Float = 1.44) {
        self.rowPitch = rowPitch
        for (r, row) in Self.rows.enumerated() {
            for (k, u) in row.unicodeScalars.enumerated() {
                let i = Int(u.value - 97)
                xs[i] = Float(k) + 0.5 + Self.offsets[r]
                ys[i] = (Float(r) + 0.5) * rowPitch
            }
        }
    }

    @inline(__always) func hasKey(_ scalar: UInt32) -> Bool { scalar >= 97 && scalar <= 122 }

    @inline(__always) func center(_ scalar: UInt32) -> (x: Float, y: Float)? {
        guard hasKey(scalar) else { return nil }
        return (xs[Int(scalar - 97)], ys[Int(scalar - 97)])
    }

    /// Squared distance from a touch to a key's center, in key widths².
    @inline(__always) func squaredDistance(x: Float, y: Float, to scalar: UInt32) -> Float {
        guard let c = center(scalar) else { return 1.44 }
        let dx = x - c.x, dy = y - c.y
        return dx * dx + dy * dy
    }

    /// AOSP's proximity: the touch is within one key width of the key's edge.
    @inline(__always) func isNear(x: Float, y: Float, to scalar: UInt32) -> Bool {
        guard let c = center(scalar) else { return false }
        let dx = max(abs(x - c.x) - 0.5, 0)
        let dy = max(abs(y - c.y) - rowPitch / 2, 0)
        return dx * dx + dy * dy < 1
    }
}

/// One typed letter: which key it produced and where the finger landed.
struct TouchPoint {
    let scalar: UInt32   // base lowercase letter
    let x: Float
    let y: Float
    let onKey: Bool

    /// `offset` is where the touch landed relative to the key's center, in
    /// key widths; nil means dead center (pasted text, tests).
    init(character: Unicode.Scalar, offset: (Float, Float)?, geometry: KeyGeometry) {
        scalar = TypingText.base(character.value)
        if let c = geometry.center(scalar) {
            x = c.x + (offset?.0 ?? 0)
            y = c.y + (offset?.1 ?? 0)
            onKey = true
        } else {
            x = 0; y = 0; onKey = false
        }
    }
}

/// Candidate search over one dictionary — AOSP LatinIME's typing traversal
/// with its cost table (FORMAT.md): match, proximity, substitution,
/// omission, insertion and transposition, beam-pruned per touch point, plus
/// completions of what's been typed so far.
enum Decoder {

    struct Kind: OptionSet {
        let rawValue: UInt16
        static let proximity = Kind(rawValue: 1)
        static let farSubstitution = Kind(rawValue: 2)
        static let firstLetterFarSubstitution = Kind(rawValue: 4)
        static let omissionSame = Kind(rawValue: 8)
        static let omissionOther = Kind(rawValue: 16)
        static let insertionSame = Kind(rawValue: 32)
        static let insertionOther = Kind(rawValue: 64)
        static let transposition = Kind(rawValue: 128)
        static let completion = Kind(rawValue: 256)
        static let trailingInsertion = Kind(rawValue: 512)
    }

    /// A dictionary node reached by some alignment of the touches.
    struct Hit {
        let node: UInt32
        /// Every non-language cost, terminal costs included.
        let spatial: Float
        let kinds: Kind
        /// No corrections at all: the typed letters spell this key.
        var exact: Bool { kinds.isEmpty }
    }

    private struct State {
        var node: UInt32
        var spatial: Float
        var proximityCount: UInt8
        var editCount: UInt8
        var depth: UInt16
        var kinds: Kind
        var last: UInt32
    }

    static let beamFirst = 310
    static let beam = 170

    /// Cheapest first; ties broken the same way on both platforms so the
    /// beam keeps the same states.
    private static func orderStates(_ a: State, _ b: State) -> Bool {
        if a.spatial != b.spatial { return a.spatial < b.spatial }
        if a.node != b.node { return a.node < b.node }
        return a.kinds.rawValue < b.kinds.rawValue
    }

    static func search(_ trie: GlydTrie, points: [TouchPoint], geometry: KeyGeometry,
                       completionLimit: Int = 8) -> [Hit] {
        let n = points.count
        guard n > 0, n <= 48 else { return [] }
        var layers = [[State]](repeating: [], count: n + 2)
        layers[0].append(State(node: 0, spatial: 0, proximityCount: 0, editCount: 0, depth: 0, kinds: [], last: 0))
        var hits: [Hit] = []

        @inline(__always) func sweet(_ x: Float) -> Float {
            if x < 0.25 { return 0.24 * x / 0.25 }
            if x < 1 { return (0.24 * (1 - x) + 1.2 * (x - 0.25)) / 0.75 }
            return 1.2
        }

        /// 0 match, 1 proximity, 2 far substitution, 3 unrelated.
        @inline(__always) func type(_ i: Int, _ b: UInt32) -> Int {
            let p = points[i]
            if b == p.scalar { return 0 }
            guard p.onKey, geometry.hasKey(b) else { return 3 }
            return geometry.isNear(x: p.x, y: p.y, to: b) ? 1 : 2
        }

        @inline(__always) func distance(_ i: Int, _ b: UInt32) -> Float {
            let p = points[i]
            guard p.onKey else { return b == p.scalar ? 0 : 1.2 }
            return geometry.squaredDistance(x: p.x, y: p.y, to: b)
        }

        @inline(__always) func matched(_ i: Int, _ b: UInt32, _ t: Int, _ s: inout State) -> Float {
            var cost = 0.1524 * sweet(distance(i, b))
            if t == 1 {
                cost += i == 0 ? 0.072 : 0.0694
                if s.proximityCount == 0 { cost += 0.07788 }
                s.proximityCount &+= 1
                s.kinds.insert(.proximity)
            }
            return cost
        }

        func push(_ layer: Int, _ s: State) {
            if s.spatial < 3 { layers[layer].append(s) }
        }

        func emit(_ s: State, trailing: Float) {
            guard trie.entryCount(s.node) > 0, s.depth > 0 else { return }
            var kinds = s.kinds
            var cost = s.spatial + trailing
            if trailing > 0 { kinds.insert(.trailingInsertion) }
            if s.proximityCount > 0 { cost += 0.0683 }
            if s.editCount > 0 || trailing > 0 { cost += 0.0362 }
            hits.append(Hit(node: s.node, spatial: cost, kinds: kinds))
        }

        for i in 0..<n {
            var layer = layers[i]
            layers[i] = []
            guard !layer.isEmpty else { continue }
            let cap = i == 0 ? beamFirst : beam
            if layer.count > cap {
                layer.sort(by: orderStates)
                layer.removeLast(layer.count - cap)
            }
            for s in layer {
                let errorsAllowed = s.spatial / Float(i + 1) < 0.095
                let first = trie.firstChild(s.node)
                if first != GlydTrie.none {
                    let end = first + trie.childCount(s.node)
                    for c in first..<end {
                        let b = TypingText.base(trie.scalar(c))
                        let t = type(i, b)

                        // Omission: the word has a letter the user didn't type.
                        if errorsAllowed && t != 0 {
                            let g0 = trie.firstChild(c)
                            if g0 != GlydTrie.none {
                                let same = s.depth > 0 && b == s.last
                                let omission: Float = s.depth == 0 ? 0.5256 : (same ? 0.345 : 0.467)
                                for g in g0..<(g0 + trie.childCount(c)) {
                                    let gb = TypingText.base(trie.scalar(g))
                                    let gt = type(i, gb)
                                    guard gt <= 1 else { continue }
                                    var next = s
                                    next.node = g
                                    next.depth += 2
                                    next.editCount &+= 1
                                    next.kinds.insert(same ? .omissionSame : .omissionOther)
                                    let cost = matched(i, gb, gt, &next)
                                    next.spatial += omission + cost
                                    next.last = gb
                                    push(i + 1, next)
                                }
                            }
                        }

                        switch t {
                        case 0, 1:
                            var next = s
                            next.node = c
                            next.depth += 1
                            let cost = matched(i, b, t, &next)
                            next.spatial += cost
                            next.last = b
                            push(i + 1, next)
                        case 2 where errorsAllowed:
                            var next = s
                            next.node = c
                            next.depth += 1
                            next.editCount &+= 1
                            next.kinds.insert(s.depth == 0 ? [.farSubstitution, .firstLetterFarSubstitution] : .farSubstitution)
                            next.spatial += 0.3806 + 0.1524 * sweet(distance(i, b))
                            next.last = b
                            push(i + 1, next)
                        default:
                            break
                        }
                    }

                    if errorsAllowed && i + 1 < n {
                        // Transposition: the next two letters typed in swapped order.
                        for c1 in first..<end {
                            let b1 = TypingText.base(trie.scalar(c1))
                            guard type(i + 1, b1) <= 1 else { continue }
                            let g0 = trie.firstChild(c1)
                            guard g0 != GlydTrie.none else { continue }
                            for c2 in g0..<(g0 + trie.childCount(c1)) {
                                let b2 = TypingText.base(trie.scalar(c2))
                                guard type(i, b2) <= 1 else { continue }
                                var next = s
                                next.node = c2
                                next.depth += 2
                                next.editCount &+= 1
                                next.kinds.insert(.transposition)
                                next.spatial += 0.5608 + 0.1524 * (distance(i + 1, b1) + distance(i, b2))
                                next.last = b2
                                push(i + 2, next)
                            }
                        }
                        // Insertion: this letter is extra; the next one continues the word.
                        let nextScalar = points[i + 1].scalar
                        let here = points[i]
                        let fatFinger = (i > 0 && points[i - 1].onKey && geometry.isNear(x: points[i - 1].x, y: points[i - 1].y, to: here.scalar))
                            || (points[i + 1].onKey && geometry.isNear(x: points[i + 1].x, y: points[i + 1].y, to: here.scalar))
                        for c in first..<end {
                            let b = TypingText.base(trie.scalar(c))
                            guard b == nextScalar else { continue }
                            let same = here.scalar == b
                            var next = s
                            next.node = c
                            next.depth += 1
                            next.editCount &+= 1
                            next.kinds.insert(same ? .insertionSame : .insertionOther)
                            next.spatial += (s.depth == 0 ? 0.639 : 0)
                                + (same ? 0.5508 : (fatFinger ? 0.674 : 0.7248))
                                + 0.1524 * distance(i + 1, b)
                            next.last = b
                            push(i + 2, next)
                        }
                    }
                }
                // The word ended one letter early: that letter was extra.
                if i == n - 1 { emit(s, trailing: 0.8128) }
            }
        }

        var finals = layers[n]
        if finals.count > beam {
            finals.sort(by: orderStates)
            finals.removeLast(finals.count - beam)
        }
        for s in finals { emit(s, trailing: 0) }
        if completionLimit > 0 {
            hits += completions(trie, from: finals, limit: completionLimit)
        }
        return hits
    }

    /// Words that continue what's been typed, best-first by cost plus the
    /// most probable word still reachable below each node.
    /// What finishing a word costs: the first letter not typed, then each after.
    static func completionCost(_ added: Int) -> Float { 0.4836 + 0.00624 * Float(added - 1) }

    private static func completions(_ trie: GlydTrie, from seeds: [State], limit: Int) -> [Hit] {
        struct Item { var node: UInt32; var spatial: Float; var added: Int; var kinds: Kind; var proximity: UInt8; var edits: UInt8; var bound: Float }
        @inline(__always) func completion(_ added: Int) -> Float { completionCost(added) }
        @inline(__always) func language(_ p: UInt8) -> Float { 1.1214 * Float(255 - Int(p)) / 255 }

        var heap = MinHeap<Item> { $0.bound != $1.bound ? $0.bound < $1.bound : $0.node < $1.node }
        for s in seeds.sorted(by: orderStates).prefix(24) where s.spatial < 0.6 {
            let first = trie.firstChild(s.node)
            guard first != GlydTrie.none else { continue }
            for c in first..<(first + trie.childCount(s.node)) where trie.maxProbability(c) > 0 {
                let item = Item(node: c, spatial: s.spatial, added: 1, kinds: s.kinds.union(.completion),
                                proximity: s.proximityCount, edits: s.editCount, bound: 0)
                heap.push(with(item) { $0.bound = $0.spatial + completion(1) + language(trie.maxProbability(c)) })
            }
        }
        var out: [Hit] = []
        var pops = 0
        while let item = heap.pop(), out.count < limit, pops < 2_000 {
            pops += 1
            if trie.entryCount(item.node) > 0 {
                var cost = item.spatial + completion(item.added)
                if item.proximity > 0 { cost += 0.0683 }
                if item.edits > 0 { cost += 0.0362 }
                out.append(Hit(node: item.node, spatial: cost, kinds: item.kinds))
            }
            guard item.added < 24 else { continue }
            let first = trie.firstChild(item.node)
            guard first != GlydTrie.none else { continue }
            for c in first..<(first + trie.childCount(item.node)) where trie.maxProbability(c) > 0 {
                var next = item
                next.node = c
                next.added += 1
                next.bound = next.spatial + completion(next.added) + language(trie.maxProbability(c))
                heap.push(next)
            }
        }
        return out
    }

    @inline(__always) private static func with<T>(_ value: T, _ change: (inout T) -> Void) -> T {
        var copy = value
        change(&copy)
        return copy
    }
}

/// A small binary heap for best-first completion.
struct MinHeap<T> {
    private var items: [T] = []
    private let less: (T, T) -> Bool

    init(_ less: @escaping (T, T) -> Bool) { self.less = less }

    var isEmpty: Bool { items.isEmpty }

    mutating func push(_ item: T) {
        items.append(item)
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard less(items[i], items[parent]) else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> T? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1
            var m = i
            if l < items.count, less(items[l], items[m]) { m = l }
            if r < items.count, less(items[r], items[m]) { m = r }
            if m == i { break }
            items.swapAt(i, m)
            i = m
        }
        return top
    }
}
