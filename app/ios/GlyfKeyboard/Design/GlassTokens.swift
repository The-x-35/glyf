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
    /// "glass" (default — translucent liquid-glass keys, dot only),
    /// "classic" (solid Apple-white), "glow" (wash + accent under-glow).
    static var keyTheme = "glass"

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
    /// Key chrome darkness: host dark mode OR any painted color/gradient.
    static var chromeDark: Bool { isDark || themedBgActive }

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
        if keyTheme == "glass" || themedBgActive {
            return chromeDark ? UIColor.white.withAlphaComponent(themedBgActive ? 0.24 : 0.14)
                              : UIColor.white.withAlphaComponent(0.58)
        }
        return chromeDark ? UIColor(red: 0.42, green: 0.42, blue: 0.44, alpha: 1) : .white
    }
    static var fillKeyPressed: UIColor {
        if keyTheme == "glass" || themedBgActive {
            return chromeDark ? UIColor.white.withAlphaComponent(0.40)
                              : UIColor.white.withAlphaComponent(0.92)
        }
        return chromeDark ? UIColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1)
                          : UIColor(white: 0.93, alpha: 1)
    }
    /// Solid version regardless of theme (press balloons, cards).
    static var fillKeySolid: UIColor {
        isDark ? UIColor(red: 0.42, green: 0.42, blue: 0.44, alpha: 1) : .white
    }
    static var fillKeySpecial: UIColor { fillKey }
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
        isDark ? UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1) : .white
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
        chromeDark ? .white : UIColor(white: 0.07, alpha: 1)
    }
    static var textSecondary: UIColor {
        chromeDark ? UIColor(white: 0.85, alpha: 1) : UIColor(white: 0.42, alpha: 1)
    }
    /// The one thing that stays constant either way: the brand keycap.
    static let brandInk = UIColor(white: 0.07, alpha: 1)

    /// Space-bar "glyf" watermark — tuned to read on EVERY theme (the old
    /// textSecondary×0.45 vanished on light glass).
    static var watermark: UIColor {
        chromeDark ? UIColor.white.withAlphaComponent(0.55)
                   : UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 0.40)
    }

    // MARK: Radii + spacing — measured against the system keyboard

    static let radiusKey: CGFloat = 9.5
    static let radiusCard: CGFloat = 18
    static let radiusSheet: CGFloat = 28
    static let unit: CGFloat = 4

    // MARK: Shadows (Apple keys: crisp 1pt drop, no blur fuzz)

    static var keyShadowOpacity: Float {
        if keyTheme == "glass" { return isDark ? 0.22 : 0.08 }
        return isDark ? 0.40 : 0.20
    }
    static let keyShadowOffset = CGSize(width: 0, height: 1)
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
        isDark ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
               : UIColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1)
    }
    static var solidKey: UIColor { fillKey }
}

extension UIColor {
    /// "RRGGBB" → color; nil on malformed input.
    convenience init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces)
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
