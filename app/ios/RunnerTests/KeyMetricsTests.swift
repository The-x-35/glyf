import XCTest

/// The system keyboard's geometry, measured off iOS 26 on four simulators and
/// pinned here so a refactor can never drift the keys away from where people
/// expect them. Each expectation is a screenshot measurement, not a guess:
/// keys were found by colour, and centres/widths read in points.
final class KeyMetricsTests: XCTestCase {

    /// width → (key width, shift width, row pitch), Apple, portrait, iOS 26.
    private let measured: [(width: CGFloat, key: CGFloat, shift: CGFloat, rowPitch: CGFloat)] = [
        (390, 32.33, 43.66, 53.78),
        (402, 33.47, 45.30, 53.77),
        (420, 35.33, 47.66, 55.89),
        (440, 37.33, 50.00, 55.89),
    ]

    func testKeyWidthMatchesTheSystemKeyboard() {
        for m in measured {
            XCTAssertEqual(KeyMetrics.keyWidth(width: m.width), m.key, accuracy: 0.2,
                           "letter width at \(m.width)pt")
        }
    }

    func testSideKeysMatchShiftAndDelete() {
        for m in measured {
            let shift = KeyMetrics.sideKeyWidth(keyWidth: KeyMetrics.keyWidth(width: m.width))
            XCTAssertEqual(shift, m.shift, accuracy: 0.5, "shift width at \(m.width)pt")
        }
    }

    /// Plus/Max-class phones get taller rows; everything narrower does not.
    func testRowPitchStepsUpOnWidePhones() {
        for m in measured {
            XCTAssertEqual(KeyMetrics.rowPitch(width: m.width), m.rowPitch, accuracy: 0.3,
                           "row pitch at \(m.width)pt")
        }
        XCTAssertEqual(KeyMetrics.keysHeight(width: 402), 216, accuracy: 0.001)
        XCTAssertEqual(KeyMetrics.keysHeight(width: 440), 224, accuracy: 0.001)
    }

    /// The whole row must land on the screen exactly: margin, ten keys, nine
    /// gaps, margin.
    func testRowsFillTheWidthExactly() {
        for m in measured {
            let total = KeyMetrics.sideMargin * 2
                + KeyMetrics.keyWidth(width: m.width) * 10
                + KeyMetrics.hGap * 9
            XCTAssertEqual(total, m.width, accuracy: 0.001, "row total at \(m.width)pt")
        }
    }

    /// The first letter's centre, which is what muscle memory actually holds.
    func testFirstKeyCentre() {
        let expected: [CGFloat: CGFloat] = [390: 22.67, 402: 23.40, 420: 24.17, 440: 25.17]
        for (w, centre) in expected {
            let c = KeyMetrics.sideMargin + KeyMetrics.keyWidth(width: w) / 2
            XCTAssertEqual(c, centre, accuracy: 0.25, "q centre at \(w)pt")
        }
    }
}
