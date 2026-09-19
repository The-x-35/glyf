import XCTest

/// "Every area should be sensitive like Apple."
///
/// Apple's keyboard has no dead space: wherever a finger lands inside the key
/// area — on a key, in the gap between two, in the margin down the side, a
/// hair above the top row — a letter comes out. These sweep EVERY point of
/// the real geometry rather than sampling a few, because the dead spots that
/// matter are the ones nobody thinks to try.
///
/// This lives in a unit test on purpose. A simulator cannot test it: its
/// touch injection only delivers touches that land on an accessibility
/// element, so a tap in a gap never reaches the process at all — no
/// hit-test, nothing. Checking it by tapping a simulator proves nothing.
final class KeyTouchTests: XCTestCase {

    /// The letter rows as KeyboardView lays them out, for one screen width.
    private func frames(width: CGFloat) -> (frames: [CGRect], pitch: CGFloat,
                                            size: CGSize) {
        let hGap = KeyMetrics.hGap
        let vGap = KeyMetrics.vGap
        let margin = KeyMetrics.sideMargin
        let availW = width - margin * 2
        let columns: CGFloat = 10
        let pitch = (availW + hGap) / columns
        let unitWidth = pitch - hGap
        let rows = KeyboardLayout.rows(mode: .letters, numberRow: false,
                                       globe: true, context: .text)
        let height = KeyMetrics.keysHeight(width: width)
        let rowH = height / CGFloat(rows.count)
        let keyH = rowH - vGap

        var out: [CGRect] = []
        for (r, row) in rows.enumerated() {
            let fixedUnits = row.map(\.units).filter { $0 > 0 }.reduce(0, +)
            let flexUnits = max(1, columns - fixedUnits)
            let rowUnits = row.contains { $0.units < 0 } ? columns : fixedUnits
            let rowWidth = rowUnits * pitch - hGap
            var x = margin + (availW - rowWidth) / 2
            let y = CGFloat(r) * rowH + vGap / 2
            for spec in row {
                let units = spec.units < 0 ? flexUnits : spec.units
                let block = units * pitch - hGap
                let w = spec.sideKey
                    ? KeyMetrics.sideKeyWidth(keyWidth: unitWidth) : block
                out.append(CGRect(x: spec.gapLeading ? x + block - w : x, y: y,
                                  width: w, height: keyH))
                x += units * pitch
            }
        }
        return (out, pitch, CGSize(width: width, height: height))
    }

    /// Not one point inside the key area may be dead — on a standard phone
    /// and on the wide class, which have different key sizes and row heights.
    func testNoDeadSpaceAnywhereInTheKeyArea() {
        for width in [CGFloat(390), 402, 420, 440] {
            let (rects, pitch, size) = frames(width: width)
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
                print("DEADSPACE width=\(width) count=\(dead.count) " +
                      "y=\(ys.prefix(6))…\(ys.suffix(3)) x=\(xs.prefix(6))…\(xs.suffix(3)) " +
                      "size=\(size)")
            }
            XCTAssertTrue(dead.isEmpty, "\(dead.count) dead points at \(width)pt")
        }
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
