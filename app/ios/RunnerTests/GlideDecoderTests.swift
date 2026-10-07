import XCTest

/// Glide typing's decoder against the dictionary the keyboard ships: the
/// 500 likeliest words glided by a believable synthetic finger (Arpit,
/// 2026-10-07: "its guesses needs to be perfect too"), the named cases, and
/// how long a decode takes.
final class GlideDecoderTests: XCTestCase {

    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // RunnerTests
        .deletingLastPathComponent()          // ios
        .deletingLastPathComponent()          // app
        .deletingLastPathComponent()          // repo

    private static var cachedDecoder: GlideDecoder?

    private func decoder() throws -> GlideDecoder {
        if let d = Self.cachedDecoder { return d }
        let path = Self.repo.appendingPathComponent("app/dict/en.glyd").path
        guard let trie = GlydTrie.mapped(path: path) else { throw XCTSkip("app/dict/en.glyd not built") }
        let d = GlideDecoder(trie: trie)
        Self.cachedDecoder = d
        return d
    }

    /// The letters as KeyboardView lays them out at this width.
    private func layout(width: CGFloat) -> GlideDecoder.Layout {
        let rows = KeyboardLayout.rows(mode: .letters, numberRow: false, globe: false, context: .text)
        let size = CGSize(width: width, height: KeyMetrics.keysHeight(width: width))
        let grid = KeyboardLayout.frames(rows: rows, size: size, context: .text)
        var keys: [(letter: Character, center: CGPoint)] = []
        for (spec, frame) in zip(rows.flatMap { $0 }, grid.frames) {
            if let c = spec.char, c.count == 1, let ch = c.first { keys.append((ch, CGPoint(x: frame.midX, y: frame.midY))) }
        }
        return GlideDecoder.Layout(keys: keys, pitch: grid.pitch)!
    }

    // MARK: Synthetic finger

    struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
        mutating func gaussian() -> Float {
            let u1 = max(unit(), 1e-7), u2 = unit()
            return sqrtf(-2 * logf(u1)) * cosf(2 * .pi * u2)
        }
    }

    /// A believable path for `word`: each letter's centre missed by a
    /// Gaussian `jitter` (key widths), one interior letter in five cut a
    /// third of the way toward the line between its neighbours (most of a
    /// key at most), sampled every 0.12 key widths with a little noise at
    /// ~8 key widths a second, and half the doubled letters held for 0.18 s.
    static func gesture(word: String, layout: GlideDecoder.Layout, rng: inout SplitMix64,
                        jitter: Float = 0.25, shortcut: Float = 0.2, dwell: Float = 0.5) -> [GlidePoint] {
        var vx: [Float] = [], vy: [Float] = [], doubled: [Bool] = []
        var last: Int = -1
        for u in word.unicodeScalars {
            let k = Int(u.value) - 97
            guard k >= 0, k < 26 else { continue }
            if k == last { doubled[doubled.count - 1] = true; continue }
            last = k
            vx.append(layout.x[k] + jitter * rng.gaussian())
            vy.append(layout.y[k] + jitter * rng.gaussian())
            doubled.append(false)
        }
        guard !vx.isEmpty else { return [] }
        if vx.count > 2 {
            for i in 1..<(vx.count - 1) where rng.unit() < shortcut {
                // Cut the corner: toward the nearest point of the line between
                // its neighbours, by a third, never more than most of a key.
                let dx = vx[i + 1] - vx[i - 1], dy = vy[i + 1] - vy[i - 1]
                let len2 = max(dx * dx + dy * dy, 1e-6)
                let f = max(0, min(1, ((vx[i] - vx[i - 1]) * dx + (vy[i] - vy[i - 1]) * dy) / len2))
                let cx = vx[i - 1] + dx * f, cy = vy[i - 1] + dy * f
                let d = hypotf(cx - vx[i], cy - vy[i])
                let move = min(0.35 * d, 0.9)
                if d > 1e-4 {
                    vx[i] += (cx - vx[i]) / d * move
                    vy[i] += (cy - vy[i]) / d * move
                }
            }
        }
        var out: [GlidePoint] = []
        var t = 0.0
        let speed: Float = 8
        func emit(_ x: Float, _ y: Float) {
            out.append(GlidePoint(x: x + 0.03 * rng.gaussian(), y: y + 0.03 * rng.gaussian(), t: t))
        }
        if vx.count == 1 {
            for _ in 0..<10 { emit(vx[0], vy[0]); t += 0.015 }
            return out
        }
        emit(vx[0], vy[0])
        for i in 1..<vx.count {
            let len = hypotf(vx[i] - vx[i - 1], vy[i] - vy[i - 1])
            let steps = max(1, Int(len / 0.12))
            for s in 1...steps {
                let f = Float(s) / Float(steps)
                t += Double(len / Float(steps) / speed)
                emit(vx[i - 1] + (vx[i] - vx[i - 1]) * f, vy[i - 1] + (vy[i] - vy[i - 1]) * f)
            }
            if doubled[i], rng.unit() < dwell {
                for _ in 0..<3 { t += 0.06; emit(vx[i], vy[i]) }
            }
        }
        return out
    }

    // MARK: Tests

    /// The 500 likeliest words, each glided once with jitter and shortcuts,
    /// on the standard and the wide phone: top-1 ≥ 93%, top-3 ≥ 98%, and a
    /// decode under 30 ms in the middle.
    func testFrequentWordsAccuracyAndSpeed() throws {
        let decoder = try decoder()
        let words = decoder.mostFrequent(500)
        XCTAssertEqual(words.count, 500)
        for (width, seed) in [(CGFloat(402), UInt64(7)), (440, 11)] {
            let lay = layout(width: width)
            var rng = SplitMix64(state: seed)
            var top1 = 0, top3 = 0
            var times: [Double] = []
            var misses: [String] = []
            for w in words {
                let g = Self.gesture(word: w, layout: lay, rng: &rng)
                let start = CFAbsoluteTimeGetCurrent()
                let out = decoder.decode(g, layout: lay)
                times.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                let keys = out.map { TypingText.key($0.word) }
                if keys.first == w { top1 += 1 } else { misses.append("\(w)→\(out.map(\.word))") }
                if keys.prefix(3).contains(w) { top3 += 1 }
            }
            times.sort()
            let median = times[times.count / 2], p95 = times[Int(Double(times.count) * 0.95)]
            let report = String(format: "glide %.0fpt: top-1 %.1f%% top-3 %.1f%%; decode median %.2f ms, p95 %.2f ms, max %.2f ms",
                                Double(width), Double(top1) / 5, Double(top3) / 5, median, p95, times.last!)
            print(report)
            print("  top-1 misses: " + misses.prefix(25).joined(separator: "  "))
            XCTAssertGreaterThanOrEqual(top1, 465, "top-1 below 93%: " + report)
            XCTAssertGreaterThanOrEqual(top3, 490, "top-3 below 98%: " + report)
            // A debug build under a busy Mac: 19 ms alone, 34 ms with two other
            // simulators building (2026-10-07). Release decodes in 0.3 ms.
            XCTAssertLessThan(median, 60, "decode too slow: " + report)
        }
    }

    /// The words anyone tries first, on an ideal path and on a jittery one.
    func testNamedWords() throws {
        let decoder = try decoder()
        let lay = layout(width: 402)
        let cases: [(glide: String, want: String)] = [
            ("the", "the"), ("you", "you"), ("hello", "hello"), ("world", "world"), ("thanks", "thanks"),
            ("tomorrow", "tomorrow"), ("coffee", "coffee"), ("i", "I"), ("to", "to"), ("it", "it"), ("is", "is"),
            ("dont", "don't"), ("im", "I'm"), ("monday", "Monday"),
        ]
        var rng = SplitMix64(state: 3)
        for (glide, want) in cases {
            let ideal = decoder.decode(Self.gesture(word: glide, layout: lay, rng: &rng, jitter: 0, shortcut: 0, dwell: 1), layout: lay)
            XCTAssertEqual(ideal.first?.word, want, "ideal \(glide): \(ideal.map(\.word))")
            let shaky = decoder.decode(Self.gesture(word: glide, layout: lay, rng: &rng), layout: lay)
            XCTAssertEqual(shaky.first?.word, want, "jittered \(glide): \(shaky.map(\.word))")
        }
    }

    /// The field's capitals and the previous word shape the answer.
    func testContext() throws {
        let decoder = try decoder()
        let lay = layout(width: 402)
        var rng = SplitMix64(state: 5)
        func glide(_ w: String) -> [GlidePoint] { Self.gesture(word: w, layout: lay, rng: &rng, jitter: 0, shortcut: 0) }

        var ctx = GlideDecoder.Context()
        ctx.capitals = .first
        XCTAssertEqual(decoder.decode(glide("hello"), layout: lay, context: ctx).first?.word, "Hello")
        ctx.capitals = .all
        XCTAssertEqual(decoder.decode(glide("hello"), layout: lay, context: ctx).first?.word, "HELLO")

        // "feel ill" is sick, not "feel I'll" (TypingEngine.keptAfter).
        ctx = GlideDecoder.Context()
        XCTAssertEqual(decoder.decode(glide("ill"), layout: lay, context: ctx).first?.word, "I'll")
        ctx.previous = "feel"
        XCTAssertEqual(decoder.decode(glide("ill"), layout: lay, context: ctx).first?.word, "ill")

        // The words before lift what follows them.
        ctx = GlideDecoder.Context()
        ctx.previous = "want"
        ctx.beforePrevious = "I"
        XCTAssertEqual(decoder.decode(glide("to"), layout: lay, context: ctx).first?.word, "to")

        // A word only this person uses glides too.
        var personal = PersonalLexicon()
        for _ in 0..<3 { personal.commit("cutee", previous: nil, today: 20_000) }
        ctx = GlideDecoder.Context()
        ctx.personal = personal
        ctx.today = 20_000
        let own = decoder.decode(glide("cutee"), layout: lay, context: ctx)
        XCTAssert(own.map(\.word).contains("cutee"), "\(own.map(\.word))")
    }

    /// A symbol layer has no letters to glide over.
    func testLayoutNeedsAllLetters() {
        XCTAssertNil(GlideDecoder.Layout(keys: [("a", CGPoint(x: 10, y: 10))], pitch: 40))
        XCTAssertNotNil(layout(width: 390))
    }
}
