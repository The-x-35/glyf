import CoreGraphics
import Foundation

/// One sample of a glide, in key widths: the touch divided by the column
/// pitch, so letters sit one apart along a row and rows about 1.25 apart.
struct GlidePoint: Equatable {
    var x: Float
    var y: Float
    /// Seconds, any zero (the touch clock).
    var t: Double
}

/// Shape writing over the .glyd trie (SHARK2: Kristensson & Zhai, 2004): a
/// glide is matched against each word's ideal path through its letters —
/// first by where it starts and ends and how far it travels, then by shape
/// (scale and position taken out) and by location — and the dictionary's
/// frequencies and word pairs settle what geometry leaves open. Pure logic:
/// KeyboardView feeds it the finger, the VC the words before the caret.
/// Arpit, 2026-10-07: "its guesses needs to be perfect too, see how perfect
/// glide typing is on iOS".
final class GlideDecoder {

    /// Where the letter keys are, in key widths.
    struct Layout: Equatable {
        var x: [Float]
        var y: [Float]

        /// From the laid-out keys; nil unless all 26 letters are there (a
        /// symbol layer or a digit pad has no glide typing).
        init?(keys: [(letter: Character, center: CGPoint)], pitch: CGFloat) {
            var x = [Float](repeating: .nan, count: 26)
            var y = x
            var found = 0
            for (letter, c) in keys {
                guard let a = letter.asciiValue, a >= 97, a <= 122, x[Int(a) - 97].isNaN else { continue }
                x[Int(a) - 97] = Float(c.x / pitch)
                y[Int(a) - 97] = Float(c.y / pitch)
                found += 1
            }
            guard found == 26, pitch > 0 else { return nil }
            self.x = x
            self.y = y
        }

        /// The typing engine's abstract grid (tests).
        init(geometry: KeyGeometry) {
            x = (97...122).map { geometry.center(UInt32($0))!.x }
            y = (97...122).map { geometry.center(UInt32($0))!.y }
        }
    }

    enum Capitals { case none, first, all }

    struct Context {
        var previous: String? = nil
        var beforePrevious: String? = nil
        var capitals: Capitals = .none
        var personal: PersonalLexicon? = nil
        var today: Int = TypingText.day()
    }

    struct Candidate: Equatable {
        var word: String
        /// Higher is better; the gap between two is in the same units.
        var score: Float
    }

    // MARK: Tuning (key widths unless said otherwise)
    //
    // Set against the 500 likeliest words glided by a synthetic finger
    // (RunnerTests/GlideDecoderTests: jitter, cut corners, dwells): 96–97%
    // top-1 and 99.8% top-3 on the standard and wide phones.

    static let samples = 32
    /// A word may start or end this far from where the finger did.
    static let endReach: Float = 1.4
    /// The finger must pass this close to every letter, in order.
    static let pruneReach: Float = 1.9
    /// Shorter or longer than the word's path by more than this is another word.
    static let lengthRatio: Float = 2.0
    /// What a path shorter or longer than the word's costs, per unit of log ratio.
    static let lengthWeight: Float = 1.0
    /// Short paths compare as if at least this long ("a" against "as").
    static let lengthFloor: Float = 0.7
    /// A gesture shorter than this never left its key: a one-letter word.
    static let stillLength: Float = 0.9
    /// Within this of the ideal path a point costs nothing.
    static let locationSlack: Float = 0.15
    /// Location after the two paths are time-aligned (dynamic time warping
    /// within `warpBand` samples): a finger that lingered or hurried over
    /// part of the word still matches it. The plain point-by-point distance
    /// only picks which words are worth aligning (`warpLimit`).
    static let warpWeight: Float = 2.4
    static let warpBand = 6
    static let warpLimit = 120
    static let shapeWeight: Float = 3
    /// Where the finger landed and lifted is deliberate: it counts double.
    static let endsWeight: Float = 0.8
    /// A sharp turn of the finger nowhere near a letter of the word.
    static let cornerPenalty: Float = 0.25
    static let cornerTurn: Float = 60 * .pi / 180
    static let cornerReach: Float = 0.9
    /// The whole span of the dictionary's frequency scale, as a cost.
    static let languageWeight: Float = 3
    /// Lingering on a key this long is a doubled letter ("hello", "too").
    static let dwellSeconds = 0.14
    static let dwellRadius: Float = 0.3
    static let dwellReach: Float = 0.8
    /// A dwell on a doubled letter; a dwell on no doubled letter; a doubled
    /// letter without a dwell (plenty of people never pause).
    static let doubleBonus: Float = 0.45
    static let dwellUnexplained: Float = 0.3
    static let doubleMiss: Float = 0.08
    /// Never seen after the previous word, when it was seen before others:
    /// ranks as if this much rarer (TypingEngine.unseenPairMost's gentler twin).
    static let unseenPairMost: Float = 25
    /// An acronym ("DJ", "PST") ranks as if this much rarer: nobody glides
    /// one, and they crowded the word floating over the finger.
    static let acronymPenalty: Float = 40

    private let trie: GlydTrie

    init(trie: GlydTrie) {
        self.trie = trie
    }

    // MARK: Word index

    /// Every glide-able word once: its letters, the trie node holding its
    /// forms, and its frequency, bucketed by first and last letter.
    private struct Index {
        var letters: [UInt8] = []        // 0–25, words back to back
        var offset: [UInt32] = [0]       // word i is letters[offset[i]..<offset[i+1]]
        var node: [UInt32] = []
        var probability: [UInt8] = []
        var bucketStart = [Int32](repeating: 0, count: 26 * 26 + 1)
        var bucketWords: [UInt32] = []
        var count: Int { node.count }
    }

    private var index: Index?
    private let indexLock = NSLock()

    /// Builds the index off the main thread, so the first glide pays nothing.
    func warm() {
        DispatchQueue.global(qos: .utility).async { [self] in _ = ensureIndex() }
    }

    private func ensureIndex() -> Index {
        indexLock.lock()
        defer { indexLock.unlock() }
        if let index { return index }
        let built = Self.build(trie)
        index = built
        return built
    }

    /// The most probable real form at a node: entries are sorted by
    /// probability, so the first that is a word is it.
    private static func bestEntry(_ trie: GlydTrie, _ node: UInt32) -> UInt32? {
        let first = trie.firstEntry(node)
        for e in first..<(first + trie.entryCount(node))
        where trie.flags(e) & (GlydTrie.flagOffensive | GlydTrie.flagNotAWord) == 0 {
            return e
        }
        return nil
    }

    private static func build(_ trie: GlydTrie) -> Index {
        var ix = Index()
        ix.letters.reserveCapacity(1_600_000)
        ix.offset.reserveCapacity(170_000)
        ix.node.reserveCapacity(170_000)
        ix.probability.reserveCapacity(170_000)
        var path = [UInt8](repeating: 0, count: 24)
        var stack: [(node: UInt32, depth: Int, letter: UInt8)] = [(0, 0, 0)]
        while let top = stack.popLast() {
            if top.depth > 0 { path[top.depth - 1] = top.letter }
            if top.depth > 0, trie.entryCount(top.node) > 0, let best = bestEntry(trie, top.node),
               trie.probability(best) > 0 {
                ix.letters.append(contentsOf: path[0..<top.depth])
                ix.offset.append(UInt32(ix.letters.count))
                ix.node.append(top.node)
                ix.probability.append(trie.probability(best))
            }
            guard top.depth < 24 else { continue }
            let first = trie.firstChild(top.node)
            guard first != GlydTrie.none else { continue }
            // Only words spelled with the 26 keys: a letter the board hasn't
            // got can't be glided over.
            for c in first..<(first + trie.childCount(top.node)) {
                let s = trie.scalar(c)
                guard s >= 97, s <= 122 else { continue }
                stack.append((c, top.depth + 1, UInt8(s - 97)))
            }
        }
        var counts = [Int32](repeating: 0, count: 26 * 26 + 1)
        for w in 0..<ix.count {
            let a = Int(ix.offset[w]), b = Int(ix.offset[w + 1])
            counts[Int(ix.letters[a]) * 26 + Int(ix.letters[b - 1]) + 1] += 1
        }
        for i in 1..<counts.count { counts[i] += counts[i - 1] }
        ix.bucketStart = counts
        ix.bucketWords = [UInt32](repeating: 0, count: ix.count)
        var fill = counts
        for w in 0..<ix.count {
            let a = Int(ix.offset[w]), b = Int(ix.offset[w + 1])
            let bucket = Int(ix.letters[a]) * 26 + Int(ix.letters[b - 1])
            ix.bucketWords[Int(fill[bucket])] = UInt32(w)
            fill[bucket] += 1
        }
        return ix
    }

    /// Tests: the likeliest words the board can glide, best first.
    func mostFrequent(_ n: Int) -> [String] {
        let ix = ensureIndex()
        let order = (0..<ix.count).sorted {
            ix.probability[$0] != ix.probability[$1] ? ix.probability[$0] > ix.probability[$1] : $0 < $1
        }
        return order.prefix(n).map { w in
            String(ix.letters[Int(ix.offset[w])..<Int(ix.offset[w + 1])].map { Character(Unicode.Scalar($0 + 97)) })
        }
    }

    // MARK: Layout cache

    private var layout: Layout?
    /// Each word's ideal path length on the current layout.
    private var templateLength: [Float] = []

    private func prepare(_ layout: Layout, _ ix: Index) {
        guard self.layout != layout || templateLength.count != ix.count else { return }
        var lengths = [Float](repeating: 0, count: ix.count)
        layout.x.withUnsafeBufferPointer { lx in
            layout.y.withUnsafeBufferPointer { ly in
                ix.letters.withUnsafeBufferPointer { letters in
                    for w in 0..<ix.count {
                        let a = Int(ix.offset[w]), b = Int(ix.offset[w + 1])
                        var total: Float = 0
                        var last = Int(letters[a])
                        for i in (a + 1)..<b {
                            let l = Int(letters[i])
                            if l == last { continue }
                            total += hypotf(lx[l] - lx[last], ly[l] - ly[last])
                            last = l
                        }
                        lengths[w] = total
                    }
                }
            }
        }
        templateLength = lengths
        self.layout = layout
    }

    // MARK: Gesture

    /// What the finger did, read once per decode. Raw buffers, not arrays:
    /// the matching below indexes them a few hundred thousand times per
    /// decode, and a debug build (the simulator's keyboard, the tests)
    /// bounds-checks every array subscript — 75 ms a glide against 1 ms
    /// optimised, before this.
    private final class Gesture {
        let x: UnsafeMutablePointer<Float>
        let y: UnsafeMutablePointer<Float>
        /// Centred and scaled so the longer side of the box is 1.
        let nx: UnsafeMutablePointer<Float>
        let ny: UnsafeMutablePointer<Float>
        /// The letters' centres, beside the path they are matched against.
        let kx: UnsafeMutablePointer<Float>
        let ky: UnsafeMutablePointer<Float>
        /// Per key, which of the 32 samples lie within `pruneReach` of it:
        /// the ordered pass over a word's letters is then a few bit ops.
        let near: UnsafeMutablePointer<UInt32>
        var length: Float = 0
        var cornersX: [Float] = []
        var cornersY: [Float] = []
        var dwellsX: [Float] = []
        var dwellsY: [Float] = []

        init(layout: Layout) {
            x = .allocate(capacity: GlideDecoder.samples)
            y = .allocate(capacity: GlideDecoder.samples)
            nx = .allocate(capacity: GlideDecoder.samples)
            ny = .allocate(capacity: GlideDecoder.samples)
            kx = .allocate(capacity: 26)
            ky = .allocate(capacity: 26)
            near = .allocate(capacity: 26)
            for k in 0..<26 {
                kx[k] = layout.x[k]
                ky[k] = layout.y[k]
            }
        }

        deinit {
            x.deallocate()
            y.deallocate()
            nx.deallocate()
            ny.deallocate()
            kx.deallocate()
            ky.deallocate()
            near.deallocate()
        }
    }

    /// Scratch for one word's ideal path, reused across the candidates.
    private final class Template {
        let vx: UnsafeMutablePointer<Float>
        let vy: UnsafeMutablePointer<Float>
        let x: UnsafeMutablePointer<Float>
        let y: UnsafeMutablePointer<Float>
        let nx: UnsafeMutablePointer<Float>
        let ny: UnsafeMutablePointer<Float>
        var rowA: UnsafeMutablePointer<Float>
        var rowB: UnsafeMutablePointer<Float>

        init() {
            vx = .allocate(capacity: 24)
            vy = .allocate(capacity: 24)
            x = .allocate(capacity: GlideDecoder.samples)
            y = .allocate(capacity: GlideDecoder.samples)
            nx = .allocate(capacity: GlideDecoder.samples)
            ny = .allocate(capacity: GlideDecoder.samples)
            rowA = .allocate(capacity: GlideDecoder.samples)
            rowB = .allocate(capacity: GlideDecoder.samples)
        }

        deinit {
            vx.deallocate()
            vy.deallocate()
            x.deallocate()
            y.deallocate()
            nx.deallocate()
            ny.deallocate()
            rowA.deallocate()
            rowB.deallocate()
        }
    }

    private static func read(_ raw: [GlidePoint], layout: Layout) -> Gesture {
        let g = Gesture(layout: layout)
        // Collapse points that didn't move.
        var xs: [Float] = [raw[0].x], ys: [Float] = [raw[0].y]
        for p in raw.dropFirst() where hypotf(p.x - xs[xs.count - 1], p.y - ys[ys.count - 1]) > 1e-4 {
            xs.append(p.x)
            ys.append(p.y)
        }
        xs.withUnsafeBufferPointer { px in
            ys.withUnsafeBufferPointer { py in
                g.length = resample(xs: px.baseAddress!, ys: py.baseAddress!, count: xs.count, intoX: g.x, intoY: g.y)
            }
        }
        normalize(x: g.x, y: g.y, intoX: g.nx, intoY: g.ny)
        for k in 0..<26 {
            var mask: UInt32 = 0
            for i in 0..<samples where hypotf(g.x[i] - g.kx[k], g.y[i] - g.ky[k]) <= pruneReach {
                mask |= 1 << UInt32(i)
            }
            g.near[k] = mask
        }
        // Corners: a smoothed copy, so jitter doesn't turn into turns.
        if g.length > 1 {
            var sx = [Float](repeating: 0, count: samples), sy = sx
            sx[0] = g.x[0]; sy[0] = g.y[0]
            sx[samples - 1] = g.x[samples - 1]; sy[samples - 1] = g.y[samples - 1]
            for i in 1..<(samples - 1) {
                sx[i] = (g.x[i - 1] + g.x[i] + g.x[i + 1]) / 3
                sy[i] = (g.y[i - 1] + g.y[i] + g.y[i + 1]) / 3
            }
            var i = 2
            while i < samples - 2 {
                let turn = angle(ax: sx[i] - sx[i - 2], ay: sy[i] - sy[i - 2], bx: sx[i + 2] - sx[i], by: sy[i + 2] - sy[i])
                if turn > cornerTurn {
                    g.cornersX.append(g.x[i])
                    g.cornersY.append(g.y[i])
                    i += 3 // one corner, not three in a row
                } else {
                    i += 1
                }
            }
        }
        // Dwells: the finger lingering inside one key, well after the start
        // and before the lift.
        if raw.count > 2, let t0 = raw.first?.t, let t1 = raw.last?.t, t1 - t0 > 0.2 {
            var i = 0
            while i < raw.count {
                var j = i
                while j + 1 < raw.count, hypotf(raw[j + 1].x - raw[i].x, raw[j + 1].y - raw[i].y) < dwellRadius { j += 1 }
                if j > i, raw[j].t - raw[i].t >= dwellSeconds, raw[i].t - t0 > 0.06, t1 - raw[j].t > 0.06 {
                    g.dwellsX.append((raw[i].x + raw[j].x) / 2)
                    g.dwellsY.append((raw[i].y + raw[j].y) / 2)
                }
                i = j + 1
            }
        }
        return g
    }

    /// `samples` points equidistant along the polyline's first `n` vertices;
    /// returns its length.
    @discardableResult
    private static func resample(xs: UnsafePointer<Float>, ys: UnsafePointer<Float>, count n: Int,
                                 intoX: UnsafeMutablePointer<Float>, intoY: UnsafeMutablePointer<Float>) -> Float {
        var total: Float = 0
        for i in 1..<max(n, 1) { total += hypotf(xs[i] - xs[i - 1], ys[i] - ys[i - 1]) }
        if total < 1e-5 {
            for i in 0..<samples { intoX[i] = xs[0]; intoY[i] = ys[0] }
            return 0
        }
        let step = total / Float(samples - 1)
        intoX[0] = xs[0]
        intoY[0] = ys[0]
        var seg = 1
        var done: Float = 0 // length of segments before `seg`
        var segLen = n > 1 ? hypotf(xs[1] - xs[0], ys[1] - ys[0]) : 0
        for i in 1..<(samples - 1) {
            let target = step * Float(i)
            while seg < n - 1, done + segLen < target {
                done += segLen
                seg += 1
                segLen = hypotf(xs[seg] - xs[seg - 1], ys[seg] - ys[seg - 1])
            }
            let f = segLen > 0 ? (target - done) / segLen : 0
            intoX[i] = xs[seg - 1] + (xs[seg] - xs[seg - 1]) * f
            intoY[i] = ys[seg - 1] + (ys[seg] - ys[seg - 1]) * f
        }
        intoX[samples - 1] = xs[n - 1]
        intoY[samples - 1] = ys[n - 1]
        return total
    }

    private static func normalize(x: UnsafePointer<Float>, y: UnsafePointer<Float>,
                                  intoX: UnsafeMutablePointer<Float>, intoY: UnsafeMutablePointer<Float>) {
        var cx: Float = 0, cy: Float = 0
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = minX, maxY = maxX
        for i in 0..<samples {
            cx += x[i]; cy += y[i]
            minX = min(minX, x[i]); maxX = max(maxX, x[i])
            minY = min(minY, y[i]); maxY = max(maxY, y[i])
        }
        cx /= Float(samples)
        cy /= Float(samples)
        let side = max(maxX - minX, maxY - minY)
        let s: Float = side > 1e-3 ? 1 / side : 0
        for i in 0..<samples {
            intoX[i] = (x[i] - cx) * s
            intoY[i] = (y[i] - cy) * s
        }
    }

    @inline(__always)
    private static func angle(ax: Float, ay: Float, bx: Float, by: Float) -> Float {
        let la = hypotf(ax, ay), lb = hypotf(bx, by)
        guard la > 1e-5, lb > 1e-5 else { return 0 }
        return acosf(max(-1, min(1, (ax * bx + ay * by) / (la * lb))))
    }

    // MARK: Decoding

    /// Ranked words for a glide, best first — at most `limit`, each already
    /// cased for the field. Empty when nothing fits.
    func decode(_ raw: [GlidePoint], layout: Layout, context: Context = Context(), limit: Int = 4) -> [Candidate] {
        guard !raw.isEmpty, limit > 0 else { return [] }
        let ix = ensureIndex()
        prepare(layout, ix)
        let g = Self.read(raw, layout: layout)
        let language = Language(trie: trie, context: context)

        struct Scored { var word: Int; var cost: Float; var letters: [UInt8]; var node: UInt32? }
        var scored: [Scored] = []
        scored.reserveCapacity(64)

        if g.length < Self.stillLength {
            // One key: the one-letter words near it, by distance and frequency.
            let px = g.x[0], py = g.y[0]
            for k in 0..<26 {
                let d = hypotf(g.kx[k] - px, g.ky[k] - py)
                guard d < 1 else { continue }
                let bucket = k * 26 + k
                for slot in Int(ix.bucketStart[bucket])..<Int(ix.bucketStart[bucket + 1]) {
                    let w = Int(ix.bucketWords[slot])
                    guard ix.offset[w + 1] - ix.offset[w] == 1 else { continue }
                    let letters = [UInt8(k)]
                    let f = language.probability(letters: letters, node: ix.node[w], base: Float(ix.probability[w]))
                    scored.append(Scored(word: w, cost: 1.5 * d + Self.languageWeight * (255 - f) / 255,
                                         letters: letters, node: ix.node[w]))
                }
            }
        } else {
            var startKeys: [Int] = [], endKeys: [Int] = []
            for k in 0..<26 {
                if hypotf(g.kx[k] - g.x[0], g.ky[k] - g.y[0]) <= Self.endReach { startKeys.append(k) }
                if hypotf(g.kx[k] - g.x[Self.samples - 1], g.ky[k] - g.y[Self.samples - 1]) <= Self.endReach {
                    endKeys.append(k)
                }
            }
            let template = Template()
            let gestureLength = max(g.length, Self.lengthFloor)
            // Everyone who passes the gates gets the rough score; only the
            // likeliest are worth aligning, which is where the time goes.
            struct Rough { var word: Int; var a: Int; var b: Int; var rough: Float }
            var roughs: [Rough] = []
            roughs.reserveCapacity(256)
            ix.letters.withUnsafeBufferPointer { letters in
                ix.offset.withUnsafeBufferPointer { offset in
                    templateLength.withUnsafeBufferPointer { lengths in
                        ix.bucketWords.withUnsafeBufferPointer { bucketWords in
                            for s in startKeys {
                                for e in endKeys {
                                    let bucket = s * 26 + e
                                    for slot in Int(ix.bucketStart[bucket])..<Int(ix.bucketStart[bucket + 1]) {
                                        let w = Int(bucketWords[slot])
                                        let ratio = max(lengths[w], Self.lengthFloor) / gestureLength
                                        guard ratio <= Self.lengthRatio, ratio >= 1 / Self.lengthRatio else { continue }
                                        let a = Int(offset[w]), b = Int(offset[w + 1])
                                        guard Self.passes(letters: letters, from: a, to: b, gesture: g) else { continue }
                                        let rough = Self.cost(letters: letters, from: a, to: b, gesture: g,
                                                              template: template, warp: false).rough
                                            + Self.lengthWeight * abs(logf(ratio))
                                            + Self.languageWeight * (255 - Float(ix.probability[w])) / 255
                                        roughs.append(Rough(word: w, a: a, b: b, rough: rough))
                                    }
                                }
                            }
                        }
                        if roughs.count > Self.warpLimit {
                            roughs.sort { $0.rough < $1.rough }
                            roughs.removeLast(roughs.count - Self.warpLimit)
                        }
                        for r in roughs {
                            let ratio = max(lengths[r.word], Self.lengthFloor) / gestureLength
                            let cost = Self.cost(letters: letters, from: r.a, to: r.b, gesture: g, template: template).total
                                + Self.lengthWeight * abs(logf(ratio))
                            scored.append(Scored(word: r.word, cost: cost, letters: Array(letters[r.a..<r.b]), node: ix.node[r.word]))
                        }
                    }
                }
            }
            // This person's own words the dictionary hasn't got ("cutee").
            if let personal = context.personal, !personal.words.isEmpty {
                for (key, _) in personal.knownForms().prefix(2_000) {
                    let letters = key.unicodeScalars.map { $0.value }
                    guard letters.count <= 24, letters.allSatisfy({ $0 >= 97 && $0 <= 122 }) else { continue }
                    let bytes = letters.map { UInt8($0 - 97) }
                    guard startKeys.contains(Int(bytes[0])), endKeys.contains(Int(bytes[bytes.count - 1])) else { continue }
                    guard let base = personal.probability(key, today: context.today) else { continue }
                    bytes.withUnsafeBufferPointer { p in
                        var total: Float = 0
                        for i in 1..<p.count where p[i] != p[i - 1] {
                            total += hypotf(g.kx[Int(p[i])] - g.kx[Int(p[i - 1])], g.ky[Int(p[i])] - g.ky[Int(p[i - 1])])
                        }
                        let ratio = max(total, Self.lengthFloor) / gestureLength
                        guard ratio <= Self.lengthRatio, ratio >= 1 / Self.lengthRatio,
                              Self.passes(letters: p, from: 0, to: p.count, gesture: g) else { return }
                        let cost = Self.cost(letters: p, from: 0, to: p.count, gesture: g, template: template).total
                            + Self.lengthWeight * abs(logf(ratio))
                        scored.append(Scored(word: -1, cost: cost + Self.languageWeight * (255 - base) / 255,
                                             letters: bytes, node: nil))
                    }
                }
            }
            for i in scored.indices where scored[i].word >= 0 {
                let f = language.probability(letters: scored[i].letters, node: scored[i].node!,
                                             base: Float(ix.probability[scored[i].word]))
                scored[i].cost += Self.languageWeight * (255 - f) / 255
            }
        }
        scored.sort { $0.cost != $1.cost ? $0.cost < $1.cost : $0.word < $1.word }

        var out: [Candidate] = []
        var seen: Set<String> = []
        for s in scored {
            let spelled: String
            if let node = s.node {
                guard let f = form(at: node, letters: s.letters, previous: language.previousKey) else { continue }
                spelled = f
            } else if let personal = context.personal,
                      let f = personal.word(String(s.letters.map { Character(Unicode.Scalar($0 + 97)) }))?.form {
                spelled = f
            } else {
                continue
            }
            let shown: String
            switch context.capitals {
            case .none: shown = spelled
            case .first: shown = TypingText.hasUppercase(spelled) ? spelled : TypingText.capitalizeFirst(spelled)
            case .all: shown = spelled.uppercased()
            }
            guard seen.insert(shown.lowercased()).inserted else { continue }
            out.append(Candidate(word: shown, score: -s.cost))
            if out.count == limit { break }
        }
        return out
    }

    /// Tests and tuning: where `word` (its letters) stood for this glide —
    /// which gate dropped it, or its costs.
    func explain(_ raw: [GlidePoint], layout: Layout, word: String, context: Context = Context()) -> String {
        let ix = ensureIndex()
        prepare(layout, ix)
        let g = Self.read(raw, layout: layout)
        let bytes = word.unicodeScalars.compactMap { $0.value >= 97 && $0.value <= 122 ? UInt8($0.value - 97) : nil }
        guard !bytes.isEmpty else { return "no letters" }
        let s = Int(bytes[0]), e = Int(bytes[bytes.count - 1])
        let startD = hypotf(g.kx[s] - g.x[0], g.ky[s] - g.y[0])
        let endD = hypotf(g.kx[e] - g.x[Self.samples - 1], g.ky[e] - g.y[Self.samples - 1])
        var line = String(format: "len %.2f start %.2f end %.2f corners %d dwells %d", g.length, startD, endD, g.cornersX.count, g.dwellsX.count)
        if startD > Self.endReach || endD > Self.endReach { return line + " DROPPED: ends" }
        var w: Int?
        for slot in Int(ix.bucketStart[s * 26 + e])..<Int(ix.bucketStart[s * 26 + e + 1]) {
            let i = Int(ix.bucketWords[slot])
            if Array(ix.letters[Int(ix.offset[i])..<Int(ix.offset[i + 1])]) == bytes { w = i; break }
        }
        guard let w else { return line + " NOT INDEXED" }
        let ratio = max(templateLength[w], Self.lengthFloor) / max(g.length, Self.lengthFloor)
        line += String(format: " ratio %.2f f %d", ratio, Int(ix.probability[w]))
        if ratio > Self.lengthRatio || ratio < 1 / Self.lengthRatio { return line + " DROPPED: length" }
        return bytes.withUnsafeBufferPointer { p in
            if !Self.passes(letters: p, from: 0, to: p.count, gesture: g) { return line + " DROPPED: passes" }
            let c = Self.cost(letters: p, from: 0, to: p.count, gesture: g, template: Template())
            let f = Language(trie: trie, context: context).probability(letters: bytes, node: ix.node[w], base: Float(ix.probability[w]))
            let length = Self.lengthWeight * abs(logf(ratio)), lang = Self.languageWeight * (255 - f) / 255
            return line + " " + c.description + String(format: " length %.2f lang %.2f total %.2f", length, lang, c.total + length + lang)
        }
    }

    /// The word's shown spelling: the dictionary's likeliest form at the
    /// node — "don't" for d-o-n-t, "I'm" for i-m, "Monday" — except where the
    /// previous word makes the plain word the one meant ("feel ill").
    private func form(at node: UInt32, letters: [UInt8], previous: String?) -> String? {
        guard let best = Self.bestEntry(trie, node) else { return nil }
        let form = trie.form(best)
        if let previous, TypingText.key(form) == String(letters.map { Character(Unicode.Scalar($0 + 97)) }),
           let kept = TypingEngine.keptAfter[TypingText.key(form)], kept.contains(previous) {
            let first = trie.firstEntry(node)
            for e in first..<(first + trie.entryCount(node))
            where trie.flags(e) & (GlydTrie.flagOffensive | GlydTrie.flagNotAWord) == 0 && trie.form(e) == TypingText.key(form) {
                return trie.form(e)
            }
        }
        return form
    }

    /// The finger passed near every letter, in order: each letter must have
    /// a sample within reach at or after the one that reached the letter before.
    @inline(__always)
    private static func passes(letters: UnsafeBufferPointer<UInt8>, from a: Int, to b: Int, gesture g: Gesture) -> Bool {
        var from: UInt32 = ~0 // samples still ahead
        var last = -1
        for i in a..<b {
            let k = Int(letters[i])
            if k == last { continue }
            last = k
            let ahead = g.near[k] & from
            if ahead == 0 { return false }
            from = ~0 << UInt32(ahead.trailingZeroBitCount)
        }
        return true
    }

    /// One word's geometric costs, apart so tuning can see them.
    struct Costs: CustomStringConvertible {
        /// Point by point, before alignment.
        var location: Float = 0
        var warped: Float = 0
        var shape: Float = 0
        var ends: Float = 0
        var corners: Float = 0
        var doubles: Float = 0
        var total: Float {
            GlideDecoder.warpWeight * warped + GlideDecoder.shapeWeight * shape
                + GlideDecoder.endsWeight * ends + GlideDecoder.cornerPenalty * corners + doubles
        }
        /// Before alignment: the same with the point-by-point distance in
        /// the warp's place, for choosing which words to align.
        var rough: Float {
            GlideDecoder.warpWeight * location + GlideDecoder.shapeWeight * shape
                + GlideDecoder.endsWeight * ends + GlideDecoder.cornerPenalty * corners + doubles
        }
        var description: String {
            String(format: "warp %.2f (rough %.2f) shape %.3f ends %.2f corners %.0f doubles %.2f = %.2f",
                   warped, location, shape, ends, corners, doubles, total)
        }
    }

    /// Everything but language: location, shape, the ends, corners, dwells.
    private static func cost(letters: UnsafeBufferPointer<UInt8>, from a: Int, to b: Int,
                             gesture g: Gesture, template t: Template, warp: Bool = true) -> Costs {
        // The ideal path: the letters' centres, doubles collapsed.
        var m = 0
        var last = -1
        var doubled: [Int] = []
        for i in a..<b {
            let k = Int(letters[i])
            if k == last { doubled.append(k); continue }
            last = k
            t.vx[m] = g.kx[k]
            t.vy[m] = g.ky[k]
            m += 1
        }
        resample(xs: t.vx, ys: t.vy, count: m, intoX: t.x, intoY: t.y)
        normalize(x: t.x, y: t.y, intoX: t.nx, intoY: t.ny)

        var location: Float = 0, shape: Float = 0
        var weights: Float = 0
        for i in 0..<samples {
            let w: Float = i == 0 || i == samples - 1 ? 2 : 1
            location += w * max(0, hypotf(g.x[i] - t.x[i], g.y[i] - t.y[i]) - locationSlack)
            weights += w
            shape += hypotf(g.nx[i] - t.nx[i], g.ny[i] - t.ny[i])
        }
        location /= weights
        // One key has no shape; where the finger went says it all.
        shape = m > 1 ? shape / Float(samples) : 0
        let ends = hypotf(g.x[0] - t.vx[0], g.y[0] - t.vy[0])
            + hypotf(g.x[samples - 1] - t.vx[m - 1], g.y[samples - 1] - t.vy[m - 1])

        var corners: Float = 0
        for c in 0..<g.cornersX.count {
            var near = false
            for v in 0..<m where hypotf(g.cornersX[c] - t.vx[v], g.cornersY[c] - t.vy[v]) <= cornerReach {
                near = true
                break
            }
            if !near { corners += 1 }
        }

        // A lingering finger wants a doubled letter there, and a doubled
        // letter wants the finger to have lingered.
        var doubles: Float = 0
        for k in doubled {
            var near = false
            for d in 0..<g.dwellsX.count where hypotf(g.dwellsX[d] - g.kx[k], g.dwellsY[d] - g.ky[k]) <= dwellReach {
                near = true
                break
            }
            doubles += near ? -doubleBonus : doubleMiss
        }
        for d in 0..<g.dwellsX.count {
            var explained = false
            for k in doubled where hypotf(g.dwellsX[d] - g.kx[k], g.dwellsY[d] - g.ky[k]) <= dwellReach {
                explained = true
                break
            }
            if !explained { doubles += dwellUnexplained }
        }
        guard warp else {
            return Costs(location: location, warped: 0, shape: shape, ends: ends, corners: corners, doubles: doubles)
        }

        // Time-aligned location: the cheapest monotone pairing of the two
        // paths, each pair costing its distance beyond the slack.
        @inline(__always) func pair(_ i: Int, _ j: Int) -> Float {
            max(0, hypotf(g.x[i] - t.x[j], g.y[i] - t.y[j]) - locationSlack)
        }
        let inf = Float.greatestFiniteMagnitude
        var rowA = t.rowA, rowB = t.rowB
        for j in 0..<samples { rowA[j] = inf }
        rowA[0] = pair(0, 0)
        for j in 1...warpBand { rowA[j] = rowA[j - 1] + pair(0, j) }
        for i in 1..<samples {
            let lo = max(0, i - warpBand), hi = min(samples - 1, i + warpBand)
            for j in 0..<samples { rowB[j] = inf }
            for j in lo...hi {
                var best = rowA[j]
                if j > 0 { best = min(best, rowB[j - 1], rowA[j - 1]) }
                rowB[j] = best + pair(i, j)
            }
            swap(&rowA, &rowB)
        }
        let warped = rowA[samples - 1] / Float(samples)
        return Costs(location: location, warped: warped, shape: shape, ends: ends, corners: corners, doubles: doubles)
    }

    // MARK: Language

    /// The frequency evidence for a word here: the dictionary's, lifted by
    /// what this person types and by the words before (FORMAT.md "Language f").
    private struct Language {
        let trie: GlydTrie
        let context: Context
        let previousKey: String?
        let followers: [UInt32: UInt8]
        let followerFloor: Float
        let triples: [UInt32: UInt8]

        init(trie: GlydTrie, context: Context) {
            self.trie = trie
            self.context = context
            let prevKey = context.previous.map(TypingText.key).flatMap { $0.isEmpty ? nil : $0 }
            previousKey = prevKey
            var followers: [UInt32: UInt8] = [:]
            var triples: [UInt32: UInt8] = [:]
            if let prevKey, let prev = Self.entry(trie, key: prevKey) {
                followers = trie.followers(prev)
                if let twoBack = context.beforePrevious.map(TypingText.key).flatMap({ Self.entry(trie, key: $0) }) {
                    for row in trie.trigrams(twoBack: twoBack, previous: prev) where triples[row.target] == nil {
                        triples[row.target] = row.probability
                    }
                }
            }
            self.followers = followers
            followerFloor = Float(followers.values.min() ?? 0)
            self.triples = triples
        }

        private static func entry(_ trie: GlydTrie, key: String) -> UInt32? {
            guard let node = trie.node(forKey: key), trie.entryCount(node) > 0 else { return nil }
            return trie.firstEntry(node)
        }

        func probability(letters: [UInt8], node: UInt32, base: Float) -> Float {
            var f = base
            let needsKey = context.personal.map { !$0.words.isEmpty } ?? false
            let key = needsKey ? String(letters.map { Character(Unicode.Scalar($0 + 97)) }) : ""
            if needsKey, let p = context.personal?.probability(key, today: context.today) { f = max(f, p) }
            var pair: Float?
            if let previousKey {
                if needsKey, let p = context.personal?.pairProbability(previous: previousKey, key, today: context.today) {
                    pair = p
                }
                if let entry = GlideDecoder.bestEntry(trie, node) {
                    if let p = followers[entry] {
                        pair = max(pair ?? 0, Float(p))
                    } else if pair == nil, !followers.isEmpty, !TypingText.hasUppercase(trie.form(entry)) {
                        f = max(min(f, followerFloor), f - GlideDecoder.unseenPairMost)
                    }
                    if let t = triples[entry] { pair = max(pair ?? 0, Float(t) + TypingEngine.tripleLift) }
                }
                if let pair { f = max(f, pair) }
            }
            if letters.count > 1, let entry = GlideDecoder.bestEntry(trie, node) {
                let form = trie.form(entry)
                if TypingText.capitalCount(form) == form.unicodeScalars.count { f = max(0, f - GlideDecoder.acronymPenalty) }
            }
            return min(max(f, 0), 255)
        }
    }
}
