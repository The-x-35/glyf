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

/// The emoji board, pinned the way the keys are. Apple's iPhone board has
/// shown four rows of bigger emoji since iOS 18.1 (Arpit's iPhone 16 Pro on
/// iOS 18.7: "normal iOS uses only 4 rows"); its chrome and proportions were
/// measured on the iOS 26.5 simulator (which still draws five rows). See
/// EmojiMetrics.
final class EmojiMetricsTests: XCTestCase {

    func testTheGridHasFourRows() {
        XCTAssertEqual(EmojiMetrics.rows, 4)
        for w: CGFloat in [390, 402, 420, 440] {
            let h = EmojiMetrics.boardHeight(width: w)
            let row = EmojiMetrics.rowPitch(boardHeight: h)
            let band = h - EmojiMetrics.gridBottomInset - EmojiMetrics.gridTop
            XCTAssertLessThanOrEqual(row * 4, band, "four rows fit at \(w)pt")
            XCTAssertGreaterThan(row * 5, band + 0.5, "a fifth row never fits at \(w)pt")
        }
    }

    /// 402pt (iPhone 16/17 Pro): 47.5pt rows, 56.9pt columns, a 39pt face
    /// drawing 36.2pt of ink, the first glyph 15.3pt in like Apple's.
    func testGlyphSizeAndPitchOnA402Phone() {
        let h = EmojiMetrics.boardHeight(width: 402)
        XCTAssertEqual(h, 305, accuracy: 0.001, "the board's height is unchanged")
        let row = EmojiMetrics.rowPitch(boardHeight: h)
        XCTAssertEqual(row, 47.5, accuracy: 0.001)
        XCTAssertEqual(EmojiMetrics.columnPitch(rowPitch: row), 56.9, accuracy: 0.05)
        XCTAssertEqual(EmojiMetrics.glyphFont(rowPitch: row), 39, accuracy: 0.001)
        XCTAssertEqual(EmojiMetrics.glyphInk(rowPitch: row), 36.2, accuracy: 0.1)
        let x0 = EmojiMetrics.gridX(rowPitch: row)
        let firstInk = x0 + (EmojiMetrics.columnPitch(rowPitch: row) - EmojiMetrics.glyphInk(rowPitch: row)) / 2
        XCTAssertEqual(firstInk, 15.3, accuracy: 0.05)
    }

    /// Bigger rows keep Apple's shape: glyph and column grow with the row.
    func testProportionsAreApples() {
        let row = EmojiMetrics.rowPitch(boardHeight: EmojiMetrics.boardHeight(width: 402))
        XCTAssertEqual(EmojiMetrics.glyphInk(rowPitch: row) / row, 29.3 / 38.4, accuracy: 0.001)
        XCTAssertEqual(EmojiMetrics.columnPitch(rowPitch: row) / row, 46.0 / 38.4, accuracy: 0.003)
        XCTAssertGreaterThan(EmojiMetrics.glyphFont(rowPitch: row), 32 * 1.2,
                             "the faces are a fifth bigger than the old five-row board's 32pt")
    }

    /// Apple's chrome: a 40pt field 9pt in, the category bar's middle 20pt
    /// off the bottom, nine glyphs 33.2pt apart.
    func testChromeMatchesApple() {
        XCTAssertEqual(EmojiMetrics.fieldHeight, 40)
        XCTAssertEqual(EmojiMetrics.fieldInset, 9)
        XCTAssertEqual(EmojiMetrics.barBottomInset - EmojiMetrics.barHeight / 2, 20, accuracy: 0.001)
        let pitch = (402 - EmojiMetrics.barX - EmojiMetrics.barTrailing) / EmojiMetrics.barCount
        XCTAssertEqual(pitch, 33.2, accuracy: 0.05)
        let h = EmojiMetrics.boardHeight(width: 402)
        let gridEnd = EmojiMetrics.gridTop + EmojiMetrics.rowPitch(boardHeight: h) * 4
        XCTAssertLessThan(gridEnd, h - EmojiMetrics.barBottomInset, "the grid ends above the bar")
    }

    /// Searching keeps the keyboard's height (Apple's does) and shows one
    /// row of 34.7pt emoji 53pt apart.
    func testSearchKeepsTheHeight() {
        XCTAssertEqual(EmojiMetrics.searchStripHeight(), Glass.toolbarHeight + EmojiMetrics.extraHeight,
                       accuracy: 0.001)
        XCTAssertEqual(EmojiMetrics.searchPitch, 53)
        XCTAssertEqual(EmojiMetrics.searchGlyphFont * EmojiMetrics.inkPerPoint, 34.7, accuracy: 0.3)
        let rowH = EmojiMetrics.searchStripHeight() - EmojiMetrics.searchRowTop
        XCTAssertGreaterThanOrEqual(rowH, EmojiMetrics.searchGlyphInk, "the row holds a face")
    }

    /// Digits and symbols keep one size whatever shift says (Apple's 22pt).
    func testSymbolsHaveNoCase() {
        XCTAssertFalse(KeyLegend.hasCase("1"))
        XCTAssertFalse(KeyLegend.hasCase("#"))
        XCTAssertTrue(KeyLegend.hasCase("a"))
        XCTAssertEqual(KeyLegend.symbolScale["*"] ?? 1, 1.48, accuracy: 0.001)
    }
}
