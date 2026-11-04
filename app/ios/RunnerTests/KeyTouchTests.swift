import XCTest

/// "Every area should be sensitive like Apple."
///
/// Apple's keyboard has no dead space: wherever a finger lands inside the key
/// area — on a key, in the gap between two, in the margin down the side, a
/// hair above the top row — a letter comes out. These sweep EVERY point of
/// the real geometry rather than sampling a few, because the dead spots that
/// matter are the ones nobody thinks to try.
///
/// This lives in a unit test on purpose, and the reason is worth keeping.
///
/// NO synthetic tap can land in a gap. Neither a simulator-control tap nor
/// XCUITest's `XCUICoordinate.tap()` reaches the keyboard unless the point
/// is on an accessibility element: a coordinate tap on a key's centre logs a
/// hit-test and types, and the same call three points to the side logs
/// nothing at all. That is provably a harness limit rather than a dead key,
/// because `KeyView` sets `isUserInteractionEnabled = false` — so to UIKit's
/// hit-test walk an on-key point and a gap point are the SAME question, both
/// answered by KeyboardView. UIKit cannot call hitTest for one and not the
/// other; a missing hit-test means the touch never arrived.
///
/// So a UI test here can never tell "the gap is dead" from "the tap was
/// never delivered" — it fails either way and looks like proof. That is how
/// dead gaps shipped twice while looking verified. Sweeping the geometry is
/// the only honest check, and it is what found the real dead strip.
final class KeyTouchTests: XCTestCase {

    /// The rows as KeyboardView lays them out, for one screen width: the
    /// same KeyboardLayout.frames the view calls.
    private func frames(width: CGFloat,
                        mode: KeyboardMode = .letters,
                        numberRow: Bool = false,
                        context: KeyboardContext = .text,
                        globe: Bool = true)
        -> (frames: [CGRect], pitch: CGFloat, size: CGSize) {
        let rows = KeyboardLayout.rows(mode: mode, numberRow: numberRow,
                                       globe: globe, context: context)
        let height = KeyMetrics.keysHeight(width: width)
            + (numberRow && !context.isPad ? Glass.numberRowExtra(width: width) : 0)
        let size = CGSize(width: width, height: height)
        let grid = KeyboardLayout.frames(rows: rows, size: size, context: context)
        return (grid.frames, grid.pitch, size)
    }

    /// Not one point inside the key area may be dead — on a standard phone
    /// and on the wide class, in EVERY layer the keyboard can show. A dead
    /// patch in the numbers layer feels exactly like one in the letters.
    func testNoDeadSpaceAnywhereInTheKeyArea() {
        var cases: [(CGFloat, KeyboardMode, Bool, KeyboardContext, String)] = []
        for width in [CGFloat(390), 402, 420, 440] {
            for mode in [KeyboardMode.letters, .symbols1, .symbols2] {
                cases.append((width, mode, false, .text, "\(mode)"))
            }
            cases.append((width, .letters, true, .text, "letters+numberRow"))
            cases.append((width, .letters, false, .email, "email"))
            cases.append((width, .letters, false, .url, "url"))
            cases.append((width, .letters, false, .webSearch, "webSearch"))
            cases.append((width, .letters, false, .twitter, "twitter"))
            cases.append((width, .symbols1, false, .numbers, "numbers"))
            cases.append((width, .letters, false, .numberPad, "numberPad"))
            cases.append((width, .letters, false, .decimalPad, "decimalPad"))
            cases.append((width, .letters, false, .phonePad, "phonePad"))
            cases.append((width, .symbols1, false, .phonePad, "phonePad symbols"))
        }
        for (width, mode, numberRow, context, label) in cases {
            let (rects, pitch, size) = frames(width: width, mode: mode,
                                              numberRow: numberRow,
                                              context: context)
            let area = CGRect(origin: .zero, size: size)
            // Addressable points only: the view spans 0..<size, so x == width
            // is one point past the last pixel a finger can land on.
            var dead: [CGPoint] = []
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let p = CGPoint(x: x, y: y)
                    if KeyHit.index(at: p, frames: rects, pitch: pitch, area: area) == nil {
                        dead.append(p)
                    }
                    x += 1
                }
                y += 1
            }
            if !dead.isEmpty {
                let ys = Set(dead.map(\.y)).sorted()
                let xs = Set(dead.map(\.x)).sorted()
                print("DEADSPACE \(label) width=\(width) count=\(dead.count) " +
                      "y=\(ys.prefix(4))…\(ys.suffix(2)) x=\(xs.prefix(4))…\(xs.suffix(2))")
            }
            XCTAssertTrue(dead.isEmpty,
                          "\(dead.count) dead points, \(label) at \(width)pt")
        }
    }

    /// Apple's rows for each field type, measured on the iOS 26.5 simulator
    /// at 402pt (and Safari's address bar on an iPhone 16 Pro): which keys,
    /// in which order, and how wide.
    func testFieldTypeRowsMatchApple() {
        func bottom(_ context: KeyboardContext, mode: KeyboardMode = .letters) -> [KeySpec] {
            KeyboardLayout.rows(mode: mode, numberRow: false, globe: false, context: context).last!
        }
        func ids(_ row: [KeySpec]) -> [String] { row.map(\.id) }
        XCTAssertEqual(ids(bottom(.text)), ["mode:123", "emojikey", "space", "return"])
        XCTAssertEqual(ids(bottom(.email)), ["mode:123", "emojikey", "space", "@", ".", "return"])
        // A web address has no space bar; Safari's address bar (a search
        // field) keeps its space bar and has no slash.
        XCTAssertEqual(ids(bottom(.url)), ["mode:123", "emojikey", ".", "/", ".com", "return"])
        XCTAssertEqual(ids(bottom(.webSearch)), ["mode:123", "emojikey", "space", ".", "return"])
        XCTAssertFalse(bottom(.webSearch).contains { $0.char == "/" })
        XCTAssertEqual(ids(bottom(.twitter)), ["mode:123", "emojikey", "space", "@", "#", "return"])
        XCTAssertEqual(ids(bottom(.numbers, mode: .symbols1)), ["mode:ABC", "space", "return"])

        // Widths at 402pt, in points, against Apple's (a Face ID phone: the
        // system draws the globe below the keys).
        func widths(_ context: KeyboardContext, mode: KeyboardMode = .letters) -> [CGFloat] {
            let (rects, _, _) = frames(width: 402, mode: mode, context: context, globe: false)
            let lastY = rects.map(\.minY).max()!
            return rects.filter { abs($0.minY - lastY) < 0.5 }.map(\.width)
        }
        func near(_ got: [CGFloat], _ want: [CGFloat], _ label: String) {
            XCTAssertEqual(got.count, want.count, label)
            for (g, w) in zip(got, want) { XCTAssertEqual(g, w, accuracy: 0.6, "\(label): \(got) vs \(want)") }
        }
        near(widths(.email), [43.3, 43.3, 92.7, 43.3, 43.3, 93.0], "email")
        near(widths(.url), [43.3, 43.3, 59.7, 60.0, 59.7, 93.0], "url")
        near(widths(.webSearch), [43.3, 43.3, 181.7, 33.3, 63.0], "webSearch")
        near(widths(.numbers, mode: .symbols1), [92.7, 191.3, 93.0], "numbers")
    }

    /// Apple's digit pads at 402pt: three 126pt keys across the full width,
    /// 48pt tall on a 54pt pitch; the corner is empty (number), the decimal
    /// separator (decimal) or +*# (phone), drawn bare like delete.
    func testDigitPadsMatchApple() {
        for context in [KeyboardContext.numberPad, .decimalPad, .phonePad] {
            let (rects, _, _) = frames(width: 402, context: context)
            XCTAssertEqual(rects.count, 12)
            XCTAssertEqual(rects[0].minX, 5.5, accuracy: 0.6)
            XCTAssertEqual(rects[2].maxX, 402 - 5.5, accuracy: 0.6)
            for r in rects {
                XCTAssertEqual(r.width, 126, accuracy: 0.6, "\(context)")
                XCTAssertEqual(r.height, 48, accuracy: 0.01, "\(context)")
            }
            XCTAssertEqual(rects[3].minY - rects[0].minY, 54, accuracy: 0.01)
            let rows = KeyboardLayout.rows(mode: .letters, numberRow: false, globe: false, context: context)
            XCTAssertEqual(rows[1][1].subtitle, "JKL")
            XCTAssertTrue(rows[3][2].bare, "delete has no key cap")
            XCTAssertTrue(rows[3][0].bare, "the corner has no key cap")
        }
        let number = KeyboardLayout.rows(mode: .letters, numberRow: false, globe: false, context: .numberPad)
        XCTAssertTrue(number[3][0].disabled, "the number pad's corner is empty")
        let phone = KeyboardLayout.rows(mode: .letters, numberRow: false, globe: false, context: .phonePad)
        XCTAssertEqual(phone[3][0].id, "mode:+*#")
        // Behind +*#: pause and wait, * and #, and +, over greyed digits.
        let more = KeyboardLayout.rows(mode: .symbols1, numberRow: false, globe: false, context: .phonePad)
        XCTAssertEqual(more[1].map { $0.title ?? $0.id }, ["pause", "5", "wait"])
        XCTAssertEqual(more[1][0].char, ",")
        XCTAssertEqual(more[1][2].char, ";")
        XCTAssertEqual(more[2].map(\.id), ["*", "8", "#"])
        XCTAssertEqual(more[3].map(\.id), ["mode:123", "+", "delete"])
        XCTAssertTrue(more[0].allSatisfy(\.disabled))
    }

    /// The strip down each side of the MIDDLE row, which is indented: beside
    /// A and beside L the nearest key is more than half a key away, so a
    /// distance limit alone left those edges dead. Apple types A and L there.
    func testIndentedMiddleRowEdgesAreNotDead() {
        for width in [CGFloat(390), 402, 420, 440] {
            let (rects, pitch, size) = frames(width: width)
            let area = CGRect(origin: .zero, size: size)
            let middle = rects.filter { abs($0.minY - rects[10].minY) < 0.5 }
            let y = middle[0].midY
            for x in [CGFloat(0), 1, 3, width - 3, width - 1, width - 0.5] {
                XCTAssertNotNil(
                    KeyHit.index(at: CGPoint(x: x, y: y), frames: rects,
                                 pitch: pitch, area: area),
                    "x=\(x) on the middle row at \(width)pt is dead")
            }
        }
    }

    /// The gaps specifically — between two keys in a row, and between rows —
    /// which is where a fast finger actually lands.
    func testGapsBetweenKeysAndRowsTypeTheNearestKey() {
        let (rects, pitch, size) = frames(width: 402)
        let area = CGRect(origin: .zero, size: size)
        let top = rects[0]                      // Q
        let second = rects[1]                   // W
        let below = rects.first { $0.minY > top.maxY }!

        let horizontal = CGPoint(x: (top.maxX + second.minX) / 2, y: top.midY)
        XCTAssertNotNil(KeyHit.index(at: horizontal, frames: rects, pitch: pitch, area: area),
                        "a touch between two keys in a row")

        let vertical = CGPoint(x: top.midX, y: (top.maxY + below.minY) / 2)
        XCTAssertNotNil(KeyHit.index(at: vertical, frames: rects, pitch: pitch, area: area),
                        "a touch between two rows")

        // The very corner where a row gap meets a column gap: the worst case.
        let corner = CGPoint(x: (top.maxX + second.minX) / 2,
                             y: (top.maxY + below.minY) / 2)
        XCTAssertNotNil(KeyHit.index(at: corner, frames: rects, pitch: pitch, area: area),
                        "a touch in the corner between four keys")
    }

    /// Above the strip is not a keystroke — the no-dead-space rule must not
    /// swallow taps meant for the suggestion bar.
    func testWellAboveTheKeysIsNotAKeystroke() {
        let (rects, pitch, size) = frames(width: 402)
        let area = CGRect(origin: .zero, size: size)
        let far = CGPoint(x: 201, y: -pitch)
        XCTAssertNil(KeyHit.index(at: far, frames: rects, pitch: pitch, area: area))
    }

    /// A touch that lands in a gap is snapped to the nearest key, so it sits
    /// OUTSIDE that key's frame. It must survive the small movement every
    /// real finger makes — measuring only from the key's frame dropped it,
    /// which is what made keys go missing when typing fast.
    func testTouchStartingInAGapSurvivesAFingerTremor() {
        let (rects, pitch, size) = frames(width: 402)
        let area = CGRect(origin: .zero, size: size)
        let top = rects[0]
        let below = rects.first { $0.minY > top.maxY }!
        let start = CGPoint(x: top.midX, y: (top.maxY + below.minY) / 2)

        let i = KeyHit.index(at: start, frames: rects, pitch: pitch, area: area)
        let key = rects[try! XCTUnwrap(i)]
        let give = KeyHit.slack(frame: key, start: start, dx: 14, dy: 16)

        for dx in [-3.0, 0, 3.0] {
            for dy in [-3.0, 0, 3.0] {
                let moved = CGPoint(x: start.x + dx, y: start.y + dy)
                XCTAssertTrue(give.contains(moved),
                              "a \(dx),\(dy)pt tremor must not cancel the key")
            }
        }
    }

    /// …but deliberately sliding away still cancels, as on Apple's keyboard.
    func testSlidingWellAwayStillCancels() {
        let (rects, _, _) = frames(width: 402)
        let key = rects[0]
        let start = CGPoint(x: key.midX, y: key.midY)
        let give = KeyHit.slack(frame: key, start: start, dx: 14, dy: 16)
        XCTAssertFalse(give.contains(CGPoint(x: key.midX + 200, y: key.midY)))
    }
}

/// The Layout settings (Keyboard › Layout): the letter layouts, the number
/// row, and the comma and period keys beside the space bar. The defaults
/// must be today's keyboard exactly, and no choice may change a key's size.
final class KeyboardLayoutChoiceTests: XCTestCase {

    private let widths: [CGFloat] = [390, 402, 420, 440]

    private func grid(width: CGFloat, mode: KeyboardMode = .letters, numberRow: Bool = false,
                      context: KeyboardContext = .text, globe: Bool = false,
                      letters: LetterLayout = .qwerty, comma: Bool = false, period: Bool = false)
        -> (rows: [[KeySpec]], frames: [CGRect], pitch: CGFloat) {
        let rows = KeyboardLayout.rows(mode: mode, numberRow: numberRow, globe: globe, context: context,
                                       letters: letters, comma: comma, period: period)
        let height = KeyMetrics.keysHeight(width: width)
            + (numberRow && !context.isPad ? Glass.numberRowExtra(width: width) : 0)
        let g = KeyboardLayout.frames(rows: rows, size: CGSize(width: width, height: height), context: context)
        return (rows, g.frames, g.pitch)
    }

    func testDefaultsAreTodaysKeyboard() {
        let fresh = GlyfSettings()
        XCTAssertNil(fresh.keyLayout)
        XCTAssertNil(fresh.commaKey)
        XCTAssertNil(fresh.periodKey)
        XCTAssertFalse(fresh.numberRow)
        XCTAssertEqual(LetterLayout(id: nil), .qwerty)
        XCTAssertEqual(LetterLayout(id: "dvorak"), .qwerty, "an unknown id is QWERTY")
        XCTAssertEqual(LetterLayout(id: "azerty"), .azerty)
        // A settings file from before these keys decodes, and reads as today's.
        let old = #"{"haptics":true,"keyClicks":true,"numberRow":false,"autocorrect":true,"autocapitalize":true,"periodShortcut":true,"candidates":true,"oneHanded":"off","toolbarOrder":["search"],"toolbarHidden":[],"bindings":{},"backendURL":"http://127.0.0.1:8787","deviceId":"x","translateTarget":"English"}"#
        let decoded = try? JSONDecoder().decode(GlyfSettings.self, from: Data(old.utf8))
        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.keyLayout)
        XCTAssertNil(decoded?.commaKey)
        for context in [KeyboardContext.text, .email, .url, .webSearch, .twitter, .numbers] {
            for mode in [KeyboardMode.letters, .symbols1, .symbols2] {
                for globe in [false, true] {
                    XCTAssertEqual(
                        KeyboardLayout.rows(mode: mode, numberRow: false, globe: globe, context: context),
                        KeyboardLayout.rows(mode: mode, numberRow: false, globe: globe, context: context,
                                            letters: LetterLayout(id: nil), comma: false, period: false))
                }
            }
        }
        // The QWERTY rows are the ones the keyboard always had.
        let ids: [[String]] = KeyboardLayout.rows(mode: .letters, numberRow: false, globe: false)
            .map { $0.map(\.id) }
        let top: [String] = "qwertyuiop".map(String.init)
        let middle: [String] = "asdfghjkl".map(String.init)
        let bottomLetters: [String] = "zxcvbnm".map(String.init)
        let third: [String] = ["shift"] + bottomLetters + ["delete"]
        let spaceRow: [String] = ["mode:123", "emojikey", "space", "return"]
        XCTAssertEqual(ids, [top, middle, third, spaceRow])
    }

    /// Every layout has the 26 letters once each, and every key lands at
    /// exactly QWERTY's size: the same key width and the same key height.
    func testLetterLayoutsKeepEveryKeySize() {
        for width in widths {
            let qwerty = grid(width: width)
            let keyW = qwerty.frames[0].width, keyH = qwerty.frames[0].height
            for letters in LetterLayout.allCases {
                let g = grid(width: width, letters: letters)
                let specs = g.rows.flatMap { $0 }
                let letterIds: [String] = specs.compactMap(\.char).filter { $0.count == 1 && $0 >= "a" && $0 <= "z" }
                let alphabet: [String] = "abcdefghijklmnopqrstuvwxyz".map(String.init)
                XCTAssertEqual(letterIds.sorted(), alphabet, "\(letters)")
                var counts: [Int] = qwerty.rows.map(\.count)
                counts[1] = letters.rows[1].count
                XCTAssertEqual(g.rows.map(\.count), counts, "\(letters) row counts")
                for (spec, f) in zip(specs, g.frames) {
                    XCTAssertEqual(f.height, keyH, accuracy: 0.001, "\(letters) \(spec.id) height")
                    if spec.isChar, spec.char?.count == 1, g.rows.last?.contains(spec) != true {
                        XCTAssertEqual(f.width, keyW, accuracy: 0.001, "\(letters) \(spec.id) width")
                    }
                }
                // shift, delete and the bottom row are QWERTY's to the point.
                let tail = qwerty.frames.count - qwerty.rows.last!.count - 1
                XCTAssertEqual(Array(g.frames.suffix(qwerty.rows.last!.count)),
                               Array(qwerty.frames.suffix(qwerty.rows.last!.count)), "\(letters) bottom row")
                XCTAssertEqual(g.frames[g.frames.count - qwerty.rows.last!.count - 1], qwerty.frames[tail],
                               "\(letters) delete")
            }
        }
    }

    /// The corrector's grid (KeyGeometry) puts every letter where the
    /// keyboard draws it, in key widths, for every layout.
    func testKeyGeometryMatchesTheDrawnKeys() {
        for letters in LetterLayout.allCases {
            let g = grid(width: 402, letters: letters)
            let geo = KeyGeometry(rows: letters.rows)
            let left = KeyMetrics.sideMargin - KeyMetrics.hGap / 2
            var rowOf: [String: Int] = [:]
            for (r, row) in g.rows.enumerated() { for s in row { if let c = s.char { rowOf[c] = r } } }
            for (spec, f) in zip(g.rows.flatMap { $0 }, g.frames) {
                guard let c = spec.char, c.count == 1, let u = c.unicodeScalars.first,
                      u.value >= 97, u.value <= 122 else { continue }
                let center = geo.center(u.value)!
                XCTAssertEqual(CGFloat(center.x), (f.midX - left) / g.pitch, accuracy: 0.001, "\(letters) \(c)")
                XCTAssertEqual(center.y, (Float(rowOf[c]!) + 0.5) * geo.rowPitch, accuracy: 0.001)
            }
        }
        // QWERTY's grid is the one the typing tests were tuned on.
        let q = KeyGeometry(), r = KeyGeometry(rows: LetterLayout.qwerty.rows)
        for u in UInt32(97)...122 {
            let a = q.center(u)!, b = r.center(u)!
            XCTAssertEqual(a.x, b.x)
            XCTAssertEqual(a.y, b.y)
        }
        // On AZERTY, a and z touch; on QWERTY they don't.
        let az = KeyGeometry(rows: LetterLayout.azerty.rows)
        let a = az.center(97)!
        XCTAssertTrue(az.isNear(x: a.x, y: a.y, to: 122))
        XCTAssertFalse(q.isNear(x: q.center(97)!.x, y: q.center(97)!.y, to: 105))
    }

    /// The comma and period keys: a text field's letters only, beside the
    /// space bar, each as wide as the emoji key, taken from the space bar.
    func testCommaAndPeriodBesideSpace() {
        for width in widths {
            let plain = grid(width: width)
            let both = grid(width: width, comma: true, period: true)
            XCTAssertEqual(both.rows.last!.map(\.id), ["mode:123", "emojikey", ",", "space", ".", "return"])
            XCTAssertEqual(grid(width: width, comma: true).rows.last!.map(\.id),
                           ["mode:123", "emojikey", ",", "space", "return"])
            XCTAssertEqual(grid(width: width, period: true).rows.last!.map(\.id),
                           ["mode:123", "emojikey", "space", ".", "return"])
            let n = both.rows.last!.count
            let row = Array(both.frames.suffix(n)), before = Array(plain.frames.suffix(4))
            XCTAssertEqual(row[2].width, row[1].width, accuracy: 0.001, "comma = emoji key")
            XCTAssertEqual(row[4].width, row[1].width, accuracy: 0.001, "period = emoji key")
            let shorter: CGFloat = before[2].width - 2.5 * both.pitch
            XCTAssertEqual(row[3].width, shorter, accuracy: 0.001)
            XCTAssertEqual(row[0], before[0]); XCTAssertEqual(row[1], before[1]); XCTAssertEqual(row[5], before[3])
            for f in row { XCTAssertEqual(f.height, before[0].height, accuracy: 0.001) }
            // Every other row is untouched.
            XCTAssertEqual(Array(both.frames.prefix(both.frames.count - n)),
                           Array(plain.frames.prefix(plain.frames.count - 4)))
            // Never on the symbols pages, which carry , and . already, nor
            // in fields with rows of their own.
            for mode in [KeyboardMode.symbols1, .symbols2] {
                XCTAssertEqual(KeyboardLayout.rows(mode: mode, numberRow: false, globe: false, comma: true, period: true),
                               KeyboardLayout.rows(mode: mode, numberRow: false, globe: false))
            }
            for context in [KeyboardContext.email, .url, .webSearch, .twitter, .numbers, .numberPad, .phonePad] {
                XCTAssertEqual(KeyboardLayout.rows(mode: .letters, numberRow: false, globe: false, context: context,
                                                   comma: true, period: true),
                               KeyboardLayout.rows(mode: .letters, numberRow: false, globe: false, context: context))
            }
        }
    }

    /// The number row is one more row of the same pitch: no key shrinks.
    func testNumberRowKeepsKeyHeight() {
        for width in widths {
            XCTAssertEqual(Glass.numberRowExtra(width: width), KeyMetrics.rowPitch(width: width))
            let plain = grid(width: width), numbers = grid(width: width, numberRow: true)
            XCTAssertEqual(numbers.rows.count, 5)
            for f in numbers.frames { XCTAssertEqual(f.height, plain.frames[0].height, accuracy: 0.001) }
            XCTAssertEqual(numbers.frames[0].width, plain.frames[0].width, accuracy: 0.001)
        }
    }
}
