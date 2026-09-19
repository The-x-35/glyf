import UIKit

/// Design tokens. The KEYBOARD follows the host like Apple's does: light by
/// default, dark when the field/system asks (or the user forces either in
/// settings). `isDark` is resolved once per appearance by the VC; every
/// surface is rebuilt on change, so tokens are plain computed values.
/// The APP stays white-only; the one accent (#7C5CFF) survives solely as the
/// bound-key dot / focus color, exactly like the logo.
/// The system keyboard's own geometry, measured off iOS 26 on four widths
/// (390, 402, 420 and 440pt) rather than guessed: the margins and gaps are
/// the same on every phone, the key width falls out of the screen width, and
/// the row height steps up once on Plus/Max-class phones. Matching this is
/// what makes Glyf feel like the keyboard people already know.
///
///     width  margin  gap  key     pitch   row     key height
///     390    6.5     6    32.30   38.30   54      43
///     402    6.5     6    33.50   39.50   54      43
///     420    6.5     6    35.30   41.30   56      45
///     440    6.5     6    37.30   43.30   56      45
///
/// The row and key-height columns were re-measured on 402 and 440 and came
/// back whole: 54/43 and 56/45, a constant 11pt gap. The 53.8/42 and 55.9/44
/// that used to sit here were a measuring artifact, not the keyboard.
enum KeyMetrics {
    /// Left and right edge inset. Constant across every phone width.
    /// 6.5 rather than 6.67: it is what the system keyboard measures, and it
    /// makes keyWidth land on Apple's to the pixel (33.5 at 402, 37.3 at 440).
    static let sideMargin: CGFloat = 6.5
    /// Gap between keys in a row. Constant.
    static let hGap: CGFloat = 6
    /// Row pitch minus key height. Constant across widths, as on Apple's.
    ///
    ///     402pt  key 43.00  pitch 54.0      440pt  key 45.00  pitch 56.0
    ///
    /// Both give a gap of exactly 11. Measure this by sweeping every column
    /// across a key and keeping the LONGEST vertical run: a single column near
    /// the key's edge is cut short by the corner radius (reads ~42.7), and a
    /// brightness-density scan across the row is cut short again (reads ~42.3).
    /// Either one invites "re-correcting" this constant to a value the system
    /// keyboard does not use -- it has been wrong both ways already.
    static let vGap: CGFloat = 11
    /// Plus/Max-class phones (414pt and wider) get the taller key rows.
    static let wideClassWidth: CGFloat = 414

    static func keyWidth(width: CGFloat) -> CGFloat {
        (width - sideMargin * 2 - hGap * 9) / 10
    }
    /// Column pitch: one letter plus one gap.
    static func pitch(width: CGFloat) -> CGFloat { keyWidth(width: width) + hGap }
    static func rowPitch(width: CGFloat) -> CGFloat {
        width >= wideClassWidth ? 56 : 54
    }
    /// The key region: four rows, 216pt on standard phones and 224 on the
    /// wide class — the same numbers the system keyboard uses.
    static func keysHeight(width: CGFloat) -> CGFloat { rowPitch(width: width) * 4 }
    /// shift, delete and the third-row mode key: a shade over 1.35 letters
    /// (measured 43.66 / 45.3 / 47.66 / 50.0 against 1.35x).
    static func sideKeyWidth(keyWidth: CGFloat) -> CGFloat { keyWidth * 1.35 }
}

enum Glass {

    /// Resolved by the keyboard VC from settings + host appearance.
    static var isDark = false
    /// Key style, user-picked in the app: "site" (default, Apple's iOS 26
    /// keys on the system sheet) or "glass" (translucent keys). Older
    /// installs may still carry "classic" or "glow".
    static var keyTheme = "site"

    /// True while the keyboard wears the default look (no theme picked).
    static var siteLook: Bool { keyTheme == "site" && !themedBgActive }

    /// The website's structure (flat cards, no surface headers): the default
    /// look and every colour theme.
    static var solidLook: Bool { keyTheme == "site" || themedBgActive }

    // MARK: Keys on the system sheet

    /// iOS draws its own keyboard sheet behind every third-party keyboard:
    /// the rounded Liquid Glass tray in apps built for iOS 26, the classic
    /// backdrop before that. It cannot be turned off and its margins cannot
    /// be painted over, so Glyf paints no board at all. Keys sit straight on
    /// the system's sheet the way Apple's do, and the sheet is whatever iOS
    /// makes it (light, dark, tinted, Reduce Transparency). A theme colours
    /// the keys, never a slab inside the tray, which is what used to show as
    /// a lighter band above the strip.
    ///
    /// Apple's keys, measured off the iOS 26 simulator: #FFFFFF on the light
    /// sheet, #404041 on the dark one, every key the same colour, no edge.
    private static let appleKeyLight = UIColor.white
    private static let appleKeyDark = UIColor(red: 0x40 / 255, green: 0x40 / 255,
                                              blue: 0x41 / 255, alpha: 1)

    /// The theme's colours with the user's dim applied; empty with no theme.
    private static var themeColors: [UIColor] {
        let k = CGFloat(1 - themeDim)
        return themeBgColors().map { cg in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(cgColor: cg).getRed(&r, green: &g, blue: &b, alpha: &a)
            return UIColor(red: r * k, green: g * k, blue: b * k, alpha: 1)
        }
    }

    /// A gradient theme runs across the whole key grid; KeyboardView masks
    /// it to the key shapes, so every key carries its own slice.
    static var keyGradient: [UIColor]? {
        let colors = themeColors
        return colors.count > 1 ? colors.map(liftedOffSheet) : nil
    }

    /// One key's colour: Apple's, the theme's, or the middle of a gradient
    /// theme (for balloons, where a slice would look torn).
    static var keyColor: UIColor {
        let colors = themeColors
        guard let first = colors.first, let last = colors.last else {
            return isDark ? appleKeyDark : appleKeyLight
        }
        return liftedOffSheet(colors.count > 1 ? first.blend(last, 0.5) : first)
    }

    /// Keys need to stand off the sheet the way Apple's do: a near-black
    /// theme would sink into the dark sheet and a near-white one would wash
    /// into the light sheet, so each moves just far enough to read as a key.
    /// Only the direction of the sheet is used, never its colour.
    private static func liftedOffSheet(_ c: UIColor) -> UIColor {
        let l = c.glyfLuminance
        if isDark && l < 0.25 { return c.blend(.white, (0.25 - l) / (1 - l)) }
        if !isDark && l > 0.80 { return c.blend(.white, 0.6) }
        return c
    }

    /// The glass look keeps its translucent keys over the sheet.
    private static var glassKeys: Bool { keyTheme == "glass" && !themedBgActive }

    /// Glyphs on keys: whichever of black and white the key can carry.
    static var keyInk: UIColor {
        if glassKeys { return textPrimary }
        return keyColor.glyfLuminance > 0.5 ? .black : .white
    }

    /// The dot on a bound key is the brand purple, unless the key is a
    /// colour purple disappears into; then it takes the glyph ink.
    static var boundDot: UIColor {
        guard themedBgActive else { return accentPrimary }
        let apart = abs(keyColor.glyfLuminance - accentPrimary.glyfLuminance)
        return apart < 0.25 ? keyInk : accentPrimary
    }

    /// The theme the keys wear: "" (none), "color:#RRGGBB" or "grad:<id>",
    /// picked on the app's Keyboard screen.
    static var themeBg = ""
    /// Gboard "borders around keys" toggle.
    static var keyBorders = false
    /// 0…0.6 background dim for color/gradient themes.
    static var themeDim: Double = 0

    /// Shared gradient table — ids match the Flutter previews exactly.
    private static let gradients: [String: [UIColor]] = [
        "dusk": [UIColor(red: 0.49, green: 0.36, blue: 1.00, alpha: 1),
                 UIColor(red: 0.93, green: 0.42, blue: 0.87, alpha: 1)],
        "ocean": [UIColor(red: 0.24, green: 0.55, blue: 1.00, alpha: 1),
                  UIColor(red: 0.25, green: 0.88, blue: 0.78, alpha: 1)],
        "ember": [UIColor(red: 1.00, green: 0.47, blue: 0.28, alpha: 1),
                  UIColor(red: 1.00, green: 0.77, blue: 0.24, alpha: 1)],
        "forest": [UIColor(red: 0.12, green: 0.66, blue: 0.41, alpha: 1),
                   UIColor(red: 0.61, green: 0.88, blue: 0.36, alpha: 1)],
    ]

    static func themeBgColors() -> [CGColor] {
        if themeBg.hasPrefix("color:#"), let c = UIColor(hex: String(themeBg.dropFirst(7))) {
            return [c.cgColor]
        }
        if themeBg.hasPrefix("grad:"), let pair = gradients[String(themeBg.dropFirst(5))] {
            return pair.map(\.cgColor)
        }
        return []
    }

    static var themedBgActive: Bool { !themeBgColors().isEmpty }
    /// Chrome (the strip, panels, hairlines) sits on the system sheet, so it
    /// follows the sheet's appearance whatever colour the keys are.
    static var chromeDark: Bool { isDark }

    // MARK: Blur (ONE layer per surface, never per key — §5.2)

    static var base: UIBlurEffect {
        UIBlurEffect(style: isDark ? .systemThinMaterialDark : .systemThinMaterialLight)
    }
    static var raised: UIBlurEffect {
        UIBlurEffect(style: isDark ? .systemMaterialDark : .systemMaterialLight)
    }
    static var overlay: UIBlurEffect {
        UIBlurEffect(style: isDark ? .systemThickMaterialDark : .systemThickMaterialLight)
    }

    // MARK: Fills — Apple-keyboard palette, both appearances

    /// Every key is the same surface (Apple's iOS 26 uniform look).
    /// Glass theme: translucent over the system sheet.
    static var fillKey: UIColor {
        if keyGradient != nil { return .clear }   // KeyboardView paints the slice
        if glassKeys {
            return isDark ? UIColor.white.withAlphaComponent(0.14)
                          : UIColor.white.withAlphaComponent(0.58)
        }
        return keyColor
    }
    static var fillKeyPressed: UIColor {
        if keyGradient != nil { return UIColor.white.withAlphaComponent(0.28) }
        if glassKeys {
            return isDark ? UIColor.white.withAlphaComponent(0.40)
                          : UIColor.white.withAlphaComponent(0.92)
        }
        return keyColor.blend(keyInk, 0.14)
    }
    /// Solid version regardless of theme (press balloons).
    static var fillKeySolid: UIColor { keyColor }
    /// Function keys (shift, delete, 123, emoji, return) wear the letter
    /// colour, as they do on iOS 26.
    static var fillKeyFn: UIColor { fillKey }
    static var fillKeyFnPressed: UIColor { fillKeyPressed }
    static var fillKeySpecial: UIColor { fillKeyFn }
    static var fillKeyGlyf: UIColor { fillKey }
    /// Bound key wash — barely-there accent over the key surface.
    static var fillKeyBound: UIColor {
        isDark ? UIColor(red: 0.36, green: 0.34, blue: 0.48, alpha: 1)
               : UIColor(red: 0.965, green: 0.955, blue: 1.0, alpha: 1)
    }
    static var fillBar: UIColor {
        isDark ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 0.72)
               : UIColor.white.withAlphaComponent(0.72)
    }
    static var fillField: UIColor {
        isDark ? UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
               : UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1)
    }
    /// Cards INSIDE keyboard surfaces (clips, tiles, results): Apple's key
    /// colour, so they read as part of the same keyboard on either sheet.
    static var surfaceCard: UIColor { isDark ? appleKeyDark : appleKeyLight }
    /// Soft chip/field fill over the sheet (the web's --kb-soft).
    static var fillSoft: UIColor {
        isDark ? UIColor.white.withAlphaComponent(0.08) : UIColor.white.withAlphaComponent(0.6)
    }
    /// Dims a panel behind a menu, over whatever the sheet is.
    static var scrim: UIColor {
        isDark ? UIColor.black.withAlphaComponent(0.55) : UIColor.white.withAlphaComponent(0.62)
    }

    // MARK: Strokes

    static var strokeHairline: UIColor {
        chromeDark ? UIColor.white.withAlphaComponent(0.10)
                   : UIColor.black.withAlphaComponent(0.08)
    }
    /// Gboard "borders around keys": a firmer outline than the hairline.
    static var strokeKeyBorder: UIColor {
        chromeDark ? UIColor.white.withAlphaComponent(0.34)
                   : UIColor.black.withAlphaComponent(0.22)
    }
    static let hairlineWidth: CGFloat = 0.5
    static var strokeFocus: UIColor { accentPrimary.withAlphaComponent(0.60) }

    // MARK: Accent + status

    static let accentPrimary = UIColor(red: 0x7C / 255, green: 0x5C / 255, blue: 0xFF / 255, alpha: 1)
    /// iMessage blue — the website's send/Replace colour.
    static let imBlue = UIColor(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255, alpha: 1)
    static let accentSuccess = UIColor(red: 0x32 / 255, green: 0xD5 / 255, blue: 0x83 / 255, alpha: 1)
    static let accentWarning = UIColor(red: 0xB7 / 255, green: 0x79 / 255, blue: 0x09 / 255, alpha: 1)
    static let accentDanger = UIColor(red: 0xF0 / 255, green: 0x44 / 255, blue: 0x38 / 255, alpha: 1)

    /// Text on the sheet and on cards. Glyphs on keys use `keyInk`, which
    /// follows the key colour instead.
    static var textPrimary: UIColor {
        isDark ? .white : UIColor(white: 0.07, alpha: 1)
    }
    static var textSecondary: UIColor {
        isDark ? UIColor(white: 0.63, alpha: 1) : UIColor(white: 0.42, alpha: 1)
    }
    /// The one thing that stays constant either way: the brand keycap.
    static let brandInk = UIColor(white: 0.07, alpha: 1)

    /// Space-bar "glyf" watermark — tuned to read on EVERY theme (the old
    /// textSecondary×0.45 vanished on light glass).
    static var watermark: UIColor { keyInk.withAlphaComponent(0.40) }

    // MARK: Radii + spacing — measured against the system keyboard

    static let radiusKey: CGFloat = 9.5
    static let radiusCard: CGFloat = 18
    static let radiusSheet: CGFloat = 28
    static let unit: CGFloat = 4

    // MARK: Shadows (Apple keys: crisp 1pt drop, no blur fuzz)

    /// iOS 26 keys are flat: no edge under them on either sheet. Only the
    /// translucent glass keys keep a faint drop to separate from the glass.
    static var keyShadowOpacity: Float {
        glassKeys ? (isDark ? 0.22 : 0.08) : 0
    }
    static var keyShadowColor: UIColor { .black }
    static var keyShadowOffset: CGSize { CGSize(width: 0, height: 1) }
    static let keyShadowRadius: CGFloat = 0

    // MARK: Motion (§5.2/§5.3 — nothing bounces)

    static let motion: TimeInterval = 0.18
    static let pressScale: CGFloat = 0.97

    enum Ripple {
        static let holdThreshold: TimeInterval = 0.32
        static let chargeRingStartScale: CGFloat = 1.18
        static let perKeyTint: TimeInterval = 0.15
        static let delayPerUnit: TimeInterval = 0.022
        static let surfaceRiseDelay: TimeInterval = 0.06
        static let reducedMotionFlash: TimeInterval = 0.12
    }

    // MARK: Heights — the strip over the system keyboard's own key region,
    // whose size comes from KeyMetrics.

    /// iOS 26 puts a 16pt band of its own sheet above every third-party
    /// keyboard and clips anything drawn into it (tested: a view placed
    /// above our top edge is cut off at the edge). So the strip is short and
    /// that band is its top padding: 16 + 36 + the keys' 6pt top gap lands
    /// the first row 58pt under the sheet's edge, against Apple's 51 and our
    /// old 66. The keys are bottom-anchored, so none of them move.
    /// The strip's own content box — the same on every iOS.
    static let stripContent: CGFloat = 36
    /// …but only iOS 26 draws that band. Older iOS puts our top edge right
    /// against the keyboard's, so the strip reads as cut off (reported from
    /// a phone on an older iOS). There we add the band ourselves; the
    /// contents then sit exactly where iOS 26 puts them.
    static let sheetBand: CGFloat = 16
    static var stripBand: CGFloat {
        if #available(iOS 26, *) { return 0 }
        return sheetBand
    }
    static var toolbarHeight: CGFloat { stripContent + stripBand }
    /// The band already pads the strip from above, so its contents sit this
    /// far above centre to look centred between the sheet edge and the keys.
    static let stripLift: CGFloat = 3
    static func keysHeight(width: CGFloat) -> CGFloat { KeyMetrics.keysHeight(width: width) }
    static func keyboardBaseHeight(width: CGFloat) -> CGFloat {
        toolbarHeight + keysHeight(width: width)
    }
    static let numberRowExtra: CGFloat = 42
    static let barExtra: CGFloat = 96      // §5.2
    static let shellExtra: CGFloat = 140   // §6.3

    // MARK: Accessibility

    static var reduceTransparency: Bool { UIAccessibility.isReduceTransparencyEnabled }
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Solid stand-in for translucent popups when Reduce Transparency is on.
    static var solidKey: UIColor { fillKeySolid }
}

extension UIColor {
    /// Perceived brightness, 0…1 (sRGB luma — good enough to pick ink).
    var glyfLuminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0.5 }
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Mix toward another colour: 0 keeps self, 1 becomes `other`.
    func blend(_ other: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 1
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 1
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return self }
        let k = max(0, min(1, t))
        return UIColor(red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k,
                       blue: b1 + (b2 - b1) * k, alpha: a1 + (a2 - a1) * k)
    }

    /// "RRGGBB" → color; nil on malformed input.
    convenience init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces)
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
