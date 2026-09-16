import UIKit

/// Design tokens. The KEYBOARD follows the host like Apple's does: light by
/// default, dark when the field/system asks (or the user forces either in
/// settings). `isDark` is resolved once per appearance by the VC; every
/// surface is rebuilt on change, so tokens are plain computed values.
/// The APP stays white-only; the one accent (#7C5CFF) survives solely as the
/// bound-key dot / focus color, exactly like the logo.
enum Glass {

    /// Resolved by the keyboard VC from settings + host appearance.
    static var isDark = false
    /// Key style, user-picked in the app (Gboard-style):
    /// "site" (default, the tryglyf.com look: solid board, white keys, grey
    /// function keys, a 2pt bottom edge), "glass" (translucent liquid glass),
    /// "classic" (solid Apple-white), "glow" (wash + accent under-glow).
    static var keyTheme = "site"

    /// True while the keyboard wears the website look, which paints a solid
    /// board instead of a blur so the palette matches tryglyf.com exactly.
    static var siteLook: Bool { keyTheme == "site" && !themedBgActive }

    /// Solid keys with a hard bottom edge: the website look, and every
    /// colour theme the user picks (those are the same keyboard in another
    /// colour, not a different material).
    static var solidLook: Bool { keyTheme == "site" || themedBgActive }

    // MARK: Derived palette

    /// Every colour in a solid keyboard comes from ONE board colour, the way
    /// Gboard builds a theme from its seed: keys are lifted off the board,
    /// function keys go the other way, and the ink is whichever of
    /// near-black / near-white the keys can actually carry. Feeding it the
    /// website's board reproduces the website's palette exactly, so themes
    /// and the default look are the same keyboard.
    struct KeyPalette {
        let board, key, keyPressed, fn, fnPressed: UIColor
        let ink, inkSoft, edge, card, soft: UIColor
        /// The ink is light: chrome (hairlines, icons) should behave as dark.
        let darkChrome: Bool

        init(board: UIColor) {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            board.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            self.board = board
            let lightBoard = board.glyfLuminance > 0.34
            if lightBoard {
                // White keys on a tinted board: Gboard's light themes and the
                // website both land here.
                key = .white
                keyPressed = key.blend(board, 0.55)
                fn = board.blend(.black, 0.14)
                fnPressed = fn.blend(.white, 0.18)
                ink = UIColor(hue: h, saturation: min(s, 0.10), brightness: 0.12, alpha: 1)
                edge = UIColor.black.withAlphaComponent(0.24)
                card = .white
                soft = UIColor.white.withAlphaComponent(0.60)
                darkChrome = false
            } else {
                key = board.blend(.white, 0.185)
                keyPressed = key.blend(.white, 0.11)
                fn = board.blend(.white, 0.07)
                fnPressed = fn.blend(.white, 0.06)
                ink = UIColor(hue: h, saturation: min(s, 0.04), brightness: 0.965, alpha: 1)
                edge = UIColor.black.withAlphaComponent(0.70)
                card = board.blend(.white, 0.065)
                soft = UIColor.white.withAlphaComponent(0.07)
                darkChrome = true
            }
            inkSoft = ink.blend(board, lightBoard ? 0.42 : 0.40)
        }
    }

    private static var paletteCache: (key: String, palette: KeyPalette)?

    static var palette: KeyPalette {
        let seed = paletteSeed
        let cacheKey = "\(themeBg)|\(isDark)|\(keyTheme)"
        if let cached = paletteCache, cached.key == cacheKey { return cached.palette }
        let made = KeyPalette(board: seed)
        paletteCache = (cacheKey, made)
        return made
    }

    /// The board colour a theme is built from: the picked colour, the middle
    /// of a picked gradient, or the website's own board.
    private static var paletteSeed: UIColor {
        let painted = themeBgColors().map { UIColor(cgColor: $0) }
        if painted.count == 1 { return painted[0] }
        if let first = painted.first, let last = painted.last, painted.count > 1 {
            return first.blend(last, 0.5)
        }
        return isDark ? Site.boardDark : Site.boardLight
    }

    // MARK: Website palette (site/app/globals.css --kb* tokens)

    /// The two board colours the website is built on (--kb). Everything else
    /// on the site — key #ffffff/#48484c, function #b5bac3/#2e2e32, ink
    /// #1d1d1f/#f5f5f7, edge, card, soft — falls out of KeyPalette to within
    /// a shade, which is why themes and the default look identical in build.
    private enum Site {
        static let boardLight = UIColor(red: 0xD5 / 255, green: 0xD8 / 255, blue: 0xDE / 255, alpha: 1)
        static let boardDark = UIColor(red: 0x1F / 255, green: 0x1F / 255, blue: 0x22 / 255, alpha: 1)
    }

    /// Painted background behind the blur: "" (stock), "color:#RRGGBB",
    /// or "grad:<id>" — picked in the app's Gboard-style theme screen.
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

    /// A colored backdrop reads as "dark chrome" — ink flips white there.
    static var themedBgActive: Bool { !themeBgColors().isEmpty }
    /// Key chrome darkness: what the ink is doing, so hairlines and icons
    /// stay legible on a pale theme as well as a deep one.
    static var chromeDark: Bool { solidLook ? palette.darkChrome : isDark }

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

    /// Every key is the same surface (Apple's current uniform look).
    /// Glass theme: translucent over the shared blur = liquid glass.
    static var fillKey: UIColor {
        if solidLook { return palette.key }
        if keyTheme == "glass" {
            return chromeDark ? UIColor.white.withAlphaComponent(0.14)
                              : UIColor.white.withAlphaComponent(0.58)
        }
        return chromeDark ? UIColor(red: 0.42, green: 0.42, blue: 0.44, alpha: 1) : .white
    }
    static var fillKeyPressed: UIColor {
        if solidLook { return palette.keyPressed }
        if keyTheme == "glass" {
            return chromeDark ? UIColor.white.withAlphaComponent(0.40)
                              : UIColor.white.withAlphaComponent(0.92)
        }
        return chromeDark ? UIColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1)
                          : UIColor(white: 0.93, alpha: 1)
    }
    /// Solid version regardless of theme (press balloons, cards).
    static var fillKeySolid: UIColor {
        if solidLook { return palette.key }
        return isDark ? UIColor(red: 0.42, green: 0.42, blue: 0.44, alpha: 1) : .white
    }
    /// Function keys (shift, delete, 123, emoji, return): a shade off the
    /// board, like Apple's and the website's.
    static var fillKeyFn: UIColor {
        solidLook ? palette.fn : fillKey
    }
    static var fillKeyFnPressed: UIColor {
        solidLook ? palette.fnPressed : fillKeyPressed
    }
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
    /// Cards and sheets INSIDE keyboard surfaces (result views, popups…).
    static var surfaceCard: UIColor {
        if solidLook { return palette.card }
        return isDark ? UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1) : .white
    }
    /// Soft chip/field fill over the board (the web's --kb-soft).
    static var fillSoft: UIColor {
        if solidLook { return palette.soft }
        return isDark ? UIColor.white.withAlphaComponent(0.08) : UIColor.white.withAlphaComponent(0.6)
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
    static let accentSuccess = UIColor(red: 0x32 / 255, green: 0xD5 / 255, blue: 0x83 / 255, alpha: 1)
    static let accentWarning = UIColor(red: 0xB7 / 255, green: 0x79 / 255, blue: 0x09 / 255, alpha: 1)
    static let accentDanger = UIColor(red: 0xF0 / 255, green: 0x44 / 255, blue: 0x38 / 255, alpha: 1)

    static var textPrimary: UIColor {
        if solidLook { return palette.ink }
        return chromeDark ? .white : UIColor(white: 0.07, alpha: 1)
    }
    static var textSecondary: UIColor {
        if solidLook { return palette.inkSoft }
        return chromeDark ? UIColor(white: 0.85, alpha: 1) : UIColor(white: 0.42, alpha: 1)
    }
    /// The one thing that stays constant either way: the brand keycap.
    static let brandInk = UIColor(white: 0.07, alpha: 1)

    /// Space-bar "glyf" watermark — tuned to read on EVERY theme (the old
    /// textSecondary×0.45 vanished on light glass).
    static var watermark: UIColor {
        if solidLook { return palette.ink.withAlphaComponent(0.40) }
        return chromeDark ? UIColor.white.withAlphaComponent(0.55)
                          : UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 0.40)
    }

    // MARK: Radii + spacing — measured against the system keyboard

    static let radiusKey: CGFloat = 9.5
    static let radiusCard: CGFloat = 18
    static let radiusSheet: CGFloat = 28
    static let unit: CGFloat = 4

    // MARK: Shadows (Apple keys: crisp 1pt drop, no blur fuzz)

    static var keyShadowOpacity: Float {
        if solidLook { return 1 }           // the colour carries the alpha
        if keyTheme == "glass" { return isDark ? 0.22 : 0.08 }
        return isDark ? 0.40 : 0.20
    }
    /// The web draws `box-shadow: 0 2px 0 var(--kb-edge)`: a hard edge under
    /// each key, not a blur.
    static var keyShadowColor: UIColor {
        solidLook ? palette.edge : .black
    }
    static var keyShadowOffset: CGSize { CGSize(width: 0, height: solidLook ? 2 : 1) }
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

    // MARK: Heights — APPLE STANDARD. Total 260pt portrait: 44 toolbar
    // (like QuickType) + 216 keys, exactly the system keyboard's key region.

    static let toolbarHeight: CGFloat = 44
    static let keysHeight: CGFloat = 216
    static let keyboardBaseHeight: CGFloat = 260
    static let numberRowExtra: CGFloat = 42
    static let barExtra: CGFloat = 96      // §5.2
    static let shellExtra: CGFloat = 140   // §6.3

    // MARK: Accessibility

    static var reduceTransparency: Bool { UIAccessibility.isReduceTransparencyEnabled }
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Solid stand-ins when Reduce Transparency is on.
    static var solidBackdrop: UIColor {
        if solidLook { return palette.board }
        return isDark ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
                      : UIColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1)
    }
    static var solidKey: UIColor { fillKey }
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
