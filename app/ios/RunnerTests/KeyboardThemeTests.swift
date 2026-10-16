import UIKit
import XCTest

/// The 29 keyboard themes (docs/THEMES.md): the generated table loads whole,
/// the contrast rules of §5.3 hold for everything the iPhone draws, and no
/// theme moves or resizes a key (§0.1).
final class KeyboardThemeTests: XCTestCase {

    private let fontsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("GlyfKeyboard/Fonts")
    private let soundsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("GlyfKeyboard/Sounds")

    override func tearDown() {
        Glass.skin = nil
        Glass.isDark = false
        ThemeFonts.activate(nil)
        ThemeFonts.directory = nil
        super.tearDown()
    }

    // MARK: The table

    func testEveryThemeLoadsBothVariants() {
        let themes = KeyboardTheme.all
        XCTAssertEqual(themes.count, 29)
        XCTAssertEqual(Set(themes.map(\.id)).count, 29, "ids are unique")
        for t in themes {
            XCTAssertEqual(KeyboardTheme.named(t.id)?.id, t.id)
            XCTAssertFalse(t.name.isEmpty)
            for dark in [false, true] {
                Glass.skin = t
                Glass.isDark = dark
                let v = t.variant(dark: dark)
                // Glass hands out exactly the variant of the sheet's mode.
                XCTAssertEqual(rgb(Glass.fillKey), v.letter.fill, "\(t.id) letter")
                XCTAssertEqual(rgb(Glass.fillKeyFn), v.function.fill, "\(t.id) function")
                XCTAssertEqual(rgb(Glass.fillKeySpace), v.space.fill, "\(t.id) space")
                XCTAssertEqual(rgb(Glass.keyInk), v.keyText, "\(t.id) ink")
                XCTAssertEqual(rgb(Glass.fnInk), v.functionGlyph, "\(t.id) fn ink")
                XCTAssertEqual(rgb(Glass.returnBlue), v.returnFill, "\(t.id) return")
                XCTAssertEqual(rgb(Glass.returnInk), v.returnText, "\(t.id) return ink")
                XCTAssertEqual(rgb(Glass.fillKeySolid), v.popupFill, "\(t.id) popup")
                XCTAssertEqual(rgb(Glass.popupInk), v.popupText, "\(t.id) popup ink")
                XCTAssertEqual(rgb(Glass.chipAccent), v.chipAccent, "\(t.id) chip accent")
                XCTAssertEqual(Glass.chipFace.map(rgb), v.chipFace, "\(t.id) chip face")
                XCTAssertEqual(rgb(Glass.boundDot), v.boundDot, "\(t.id) dot")
                XCTAssertEqual(Glass.keyFaceShadow.offset.height, CGFloat(v.shadow.offsetY))
            }
            XCTAssertTrue(t.light.letter.fill != t.dark.letter.fill || t.light.keyText != t.dark.keyText
                          || t.light.returnFill != t.dark.returnFill || t.light.border != nil || t.dark.border != nil,
                          "\(t.id): light and dark are two variants")
            if let font = t.font {
                let url = fontsDir.appendingPathComponent(font.file + "." + font.ext)
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(t.id) font \(url.lastPathComponent)")
                let licence = fontsDir.appendingPathComponent(font.family.replacingOccurrences(of: " ", with: "") + "-OFL.txt")
                XCTAssertTrue(FileManager.default.fileExists(atPath: licence.path), "\(t.id) OFL.txt")
            }
            for role in t.sound.roles {
                let name = ["letter": ThemeSoundRole.letter, "space": .space, "delete": .delete, "return": .ret]
                    .first { $0.value == role }!.key
                let url = soundsDir.appendingPathComponent("theme-\(t.sound.name)-\(name).caf")
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(t.id) \(url.lastPathComponent)")
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? NSNumber)?.intValue ?? .max
                XCTAssertLessThanOrEqual(size, 20_000, "\(url.lastPathComponent) under 20 KB")
            }
        }
    }

    func testNoSkinIsTodaysLook() {
        XCTAssertNil(KeyboardTheme.named(nil))
        XCTAssertNil(KeyboardTheme.named(""))
        XCTAssertNil(KeyboardTheme.named("spiderman"), "an unknown id falls back to today's look")
        Glass.skin = nil
        Glass.isDark = false
        XCTAssertEqual(rgb(Glass.fillKey), 0xFFFFFF)
        XCTAssertEqual(rgb(Glass.returnBlue), 0x007AFF)
        XCTAssertEqual(Glass.keyFont(ofSize: 24.5), UIFont.systemFont(ofSize: 24.5))
    }

    /// A settings file from before themes decodes, with no theme and the
    /// theme sounds on.
    func testOldSettingsDecodeWithoutASkin() throws {
        let old = try JSONEncoder().encode(GlyfSettings())
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        dict.removeValue(forKey: "skin")
        dict.removeValue(forKey: "skinSound")
        let data = try JSONSerialization.data(withJSONObject: dict)
        let s = try JSONDecoder().decode(GlyfSettings.self, from: data)
        XCTAssertNil(KeyboardTheme.named(s.skin))
        XCTAssertTrue(s.skinSound ?? true)
        dict["skin"] = "typewriter"
        let themed = try JSONDecoder().decode(GlyfSettings.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(KeyboardTheme.named(themed.skin)?.name, "Typewriter")
    }

    // MARK: Contrast (§5.3, the iPhone's share of shared/themes/check_contrast.py)

    /// The sheets iOS draws behind a keyboard, measured: light and the
    /// forced paint, dark and its lighter twin.
    private let sheets: [Bool: [UInt32]] = [false: [0xE2E4E8, 0xD1D4D9], true: [0x1B1B1D, 0x292929]]

    func testContrastRulesHold() {
        var failures: [String] = []
        for t in KeyboardTheme.all {
            for dark in [false, true] {
                let v = t.variant(dark: dark)
                let mode = dark ? "dark" : "light"
                func need(_ what: String, _ value: Double, _ min: Double) {
                    if value < min - 1e-9 { failures.append(String(format: "%@ %@: %@ %.2f < %.1f", t.id, mode, what, value, min)) }
                }
                // Text 4.5:1. Marble's veins lie under the letters: the
                // worst point is the fill blended toward the ink.
                let veins = t.keyTexture?.kind == .veins ? t.keyTexture!.amplitude : 0
                need("key text", ratio(v.keyText, blend(v.letter.fill, v.keyText, veins)), 4.5)
                need("function glyph", ratio(v.functionGlyph, v.function.fill), 4.5)
                if t.keyTexture?.kind == .satin {
                    // Rose Gold's sheen: checked at both ends of the gradient.
                    for end in ThemeTextures.satin(v.function.fill, glyph: v.functionGlyph) {
                        need("function glyph on satin", ratio(v.functionGlyph, rgb(UIColor(cgColor: end))), 4.5)
                    }
                }
                for (name, o) in [("shift", v.shift), ("delete", v.delete)] {
                    if let o { need(name + " glyph", ratio(o.glyph, o.fill), 4.5) }
                }
                need("return text", ratio(v.returnText, v.returnFill), 4.5)
                need("popup text", ratio(v.popupText, v.popupFill), 4.5)
                need("chip accent", ratio(v.chipAccent, v.chipFace), 4.5)
                // Non-text 3:1: the dot on its key, every key on the sheet.
                need("bound dot", ratio(v.boundDot, v.letter.fill), 3.0)
                var keys: [(ThemeKeyClass, UInt32)] = [(.letter, v.letter.fill), (.function, v.function.fill),
                                                       (.space, v.space.fill), (.ret, v.returnFill)]
                keys += [v.shift, v.delete].compactMap { $0 }.map { (.function, $0.fill) }
                for (cls, fill) in keys {
                    let worst = sheets[dark]!.map { boundary(fill, cls, $0, v) }.min()!
                    need("\(cls) key vs iPhone sheet", worst, 1.15)
                }
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    /// The text on a themed chip reads against the chip's own face, which
    /// can be dark on a light sheet.
    func testChipTextReadsOnEveryFace() {
        for t in KeyboardTheme.all {
            for dark in [false, true] {
                Glass.skin = t
                Glass.isDark = dark
                let face = t.variant(dark: dark).chipFace
                XCTAssertGreaterThanOrEqual(ratio(rgb(Glass.chipText), face), 4.5, "\(t.id) \(dark)")
            }
        }
    }

    // MARK: Geometry (§0.1): a theme never moves or resizes a key

    func testKeyMetricsAreIdenticalWithASkin() {
        func snapshot() -> [String] {
            var out: [String] = []
            for w: CGFloat in [390, 402, 420, 440] {
                out.append("\(KeyMetrics.keyWidth(width: w)) \(KeyMetrics.pitch(width: w)) \(KeyMetrics.rowPitch(width: w)) "
                           + "\(KeyMetrics.keysHeight(width: w)) \(KeyMetrics.sideKeyWidth(keyWidth: KeyMetrics.keyWidth(width: w))) "
                           + "\(Glass.keyboardBaseHeight(width: w))")
                for context in [KeyboardContext.text, .email, .url, .webSearch, .numberPad, .decimalPad, .phonePad] {
                    for mode in [KeyboardMode.letters, .symbols1, .symbols2] {
                        for numberRow in [false, true] {
                            let rows = KeyboardLayout.rows(mode: mode, numberRow: numberRow, globe: true, context: context)
                            let g = KeyboardLayout.frames(rows: rows, size: CGSize(width: w, height: KeyMetrics.keysHeight(width: w)),
                                                          context: context)
                            out.append("\(g.pitch) \(g.unitWidth) \(g.rowHeight) " + g.frames.map { "\($0)" }.joined(separator: ","))
                        }
                    }
                }
            }
            out.append("\(KeyMetrics.sideMargin) \(KeyMetrics.hGap) \(KeyMetrics.vGap) \(Glass.radiusKey) \(Glass.radiusCard) "
                       + "\(Glass.stripContent) \(Glass.stripBand) \(Glass.stripLift) \(Glass.toolbarHeight) \(Glass.hairlineWidth)")
            return out
        }
        Glass.skin = nil
        let plain = snapshot()
        for t in KeyboardTheme.all {
            for dark in [false, true] {
                Glass.skin = t
                Glass.isDark = dark
                XCTAssertEqual(snapshot(), plain, "\(t.id) \(dark ? "dark" : "light") moved a key")
                // Borders are 1pt inside the key's bounds; shadows offset 0
                // or 1 with a radius of at most 4 — neither grows a key.
                if let b = t.variant(dark: dark).border { XCTAssertEqual(b.width, 1) }
                XCTAssertLessThanOrEqual(Glass.keyFaceShadow.radius, 4)
            }
        }
    }

    /// A theme's face at today's sizes: it loads from the bundle's file, at
    /// exactly the point size the system face uses, and the widest letters
    /// fit a 33.5pt key (402pt phones) without the label shrinking them
    /// (§8.3 "No shrink"). The sizes are never changed to make one fit.
    func testThemeFontsLoadAtTodaysSizesWithoutShrinking() {
        ThemeFonts.directory = fontsDir
        var tooWide: [String] = []
        for t in KeyboardTheme.all {
            guard let font = t.font else { continue }
            Glass.skin = t
            ThemeFonts.activate(font)
            let ps = ThemeFonts.activePostScriptName
            XCTAssertNotNil(ps, "\(t.id): \(font.file) registered")
            for size: CGFloat in [24.5, 22] {
                let f = Glass.keyFont(ofSize: size)
                XCTAssertEqual(f.pointSize, size, "\(t.id) keeps \(size)pt")
                // A variable face comes back as its named instance
                // (Orbitron-Medium for 500), so compare the family.
                XCTAssertEqual(f.familyName, ps.flatMap { UIFont(name: $0, size: size) }?.familyName,
                               "\(t.id) uses its own face")
                XCTAssertNotEqual(f.familyName, UIFont.systemFont(ofSize: size).familyName, "\(t.id) not the system face")
                for s in ["m", "w", "M", "W"] where (size == 22) == (s == s.uppercased()) {
                    let w = (s as NSString).size(withAttributes: [.font: f]).width
                    if w > 33.5 { tooWide.append(String(format: "%@ %@ %.1fpt", t.id, s, w)) }
                }
            }
        }
        XCTAssertEqual(tooWide, [], "letters too wide for a 33.5pt key: \(tooWide)")
    }

    // MARK: Helpers (WCAG 2.x, as check_contrast.py)

    private func rgb(_ c: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32((r * 255).rounded()) << 16 | UInt32((g * 255).rounded()) << 8 | UInt32((b * 255).rounded())
    }

    private func channels(_ c: UInt32) -> [Double] {
        [Double((c >> 16) & 0xFF) / 255, Double((c >> 8) & 0xFF) / 255, Double(c & 0xFF) / 255]
    }

    private func lum(_ c: UInt32) -> Double {
        let f = { (v: Double) in v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let ch = channels(c).map(f)
        return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]
    }

    private func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (lum(a), lum(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        let x = channels(a), y = channels(b)
        let m = zip(x, y).map { UInt32(((($0 + ($1 - $0) * t) * 255)).rounded()) }
        return m[0] << 16 | m[1] << 8 | m[2]
    }

    /// A key's boundary against `bg`: its fill, its 1pt border, or its 1pt
    /// bottom edge (an offset-1, radius-0 shadow composited over the sheet).
    private func boundary(_ fill: UInt32, _ cls: ThemeKeyClass, _ bg: UInt32, _ v: ThemeVariant) -> Double {
        var best = ratio(fill, bg)
        if let b = v.border, b.appliesTo.contains(cls) { best = max(best, ratio(b.color, bg)) }
        let s = v.shadow
        if s.offsetY >= 1, s.radius == 0, s.alpha > 0 { best = max(best, ratio(blend(bg, s.color, s.alpha), bg)) }
        return best
    }
}
