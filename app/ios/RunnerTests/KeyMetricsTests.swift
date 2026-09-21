import UIKit
import XCTest

/// The system keyboard's geometry, measured off iOS 26 on four simulators and
/// pinned here so a refactor can never drift the keys away from where people
/// expect them. Each expectation is a screenshot measurement, not a guess:
/// keys were found by colour, and centres/widths read in points.
final class KeyMetricsTests: XCTestCase {

    /// width → (key width, shift width, row pitch, key height), Apple,
    /// portrait, iOS 26. The 402 and 440 rows are direct measurements; 390 and
    /// 420 follow from them, since margin, gap and the 11pt row gap are all
    /// constant and only the width class changes the row.
    ///
    /// Measure a key by sweeping EVERY column across it and keeping the
    /// longest vertical run. One column near the edge is cut short by the
    /// corner radius, and a brightness-density scan across the row is cut
    /// short again; both under-read the height by roughly a point and have
    /// twice sent this file's numbers the wrong way.
    private let measured: [(width: CGFloat, key: CGFloat, shift: CGFloat,
                            rowPitch: CGFloat, keyHeight: CGFloat)] = [
        (390, 32.30, 43.66, 54, 43),
        (402, 33.50, 45.30, 54, 43),
        (420, 35.30, 47.66, 56, 45),
        (440, 37.30, 50.00, 56, 45),
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
            XCTAssertEqual(KeyMetrics.rowPitch(width: m.width), m.rowPitch, accuracy: 0.05,
                           "row pitch at \(m.width)pt")
        }
        XCTAssertEqual(KeyMetrics.keysHeight(width: 402), 216, accuracy: 0.001)
        XCTAssertEqual(KeyMetrics.keysHeight(width: 440), 224, accuracy: 0.001)
    }

    /// A key stands `rowPitch - vGap` tall. This is the number that has drifted
    /// twice, in both directions, so it is pinned per width class: 43 on a
    /// standard phone and 45 on the wide class, from one constant 11pt gap.
    func testKeyHeightMatchesTheSystemKeyboard() {
        for m in measured {
            let h = KeyMetrics.rowPitch(width: m.width) - KeyMetrics.vGap
            XCTAssertEqual(h, m.keyHeight, accuracy: 0.05,
                           "key height at \(m.width)pt")
        }
    }

    /// The gap between rows is one number on every phone, as on Apple's.
    func testRowGapIsConstantAcrossWidthClasses() {
        for m in measured {
            XCTAssertEqual(m.rowPitch - m.keyHeight, KeyMetrics.vGap, accuracy: 0.05,
                           "row gap at \(m.width)pt")
        }
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
