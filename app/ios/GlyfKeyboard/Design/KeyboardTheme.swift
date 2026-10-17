import AudioToolbox
import CoreText
import UIKit

// MARK: - The theme table's types (data: KeyboardThemes.swift, generated)

/// The key classes a theme border can go on (docs/THEMES.md §5.1). `ret` is
/// the primary return (go, search, send, done); a plain return is a
/// function key.
enum ThemeKeyClass: Hashable { case letter, function, space, ret }

/// A key class's fill and its pressed shade, as 0xRRGGBB.
struct ThemeFill { let fill: UInt32; let pressed: UInt32 }

/// Shift's or delete's own colours (Primary's red shift and blue delete).
struct ThemeOverride { let fill: UInt32; let glyph: UInt32; let pressed: UInt32 }

/// The key's shadow: an edge (offset 1, radius 0) or a glow (offset 0,
/// radius 2 to 4).
struct ThemeShadow { let color: UInt32; let alpha: Double; let offsetY: Double; let radius: Double }

/// A 1pt border, drawn inside the key's bounds, on the classes named.
struct ThemeBorder { let color: UInt32; let width: Double; let appliesTo: Set<ThemeKeyClass> }

/// One appearance of a theme. iOS paints no board, so there is none here.
struct ThemeVariant {
    let letter: ThemeFill
    let function: ThemeFill
    let space: ThemeFill
    let keyText: UInt32
    let functionGlyph: UInt32
    let returnFill: UInt32
    let returnText: UInt32
    let returnPressed: UInt32
    let shift: ThemeOverride?
    let delete: ThemeOverride?
    let popupFill: UInt32
    let popupText: UInt32
    let chipFace: UInt32
    let chipAccent: UInt32
    let boundDot: UInt32
    let shadow: ThemeShadow
    let border: ThemeBorder?
    /// The finish: faces, legends and ornaments (shared/themes/styles.py).
    let style: ThemeStyle
}

// MARK: - The finish (shared/themes/styles.py; reference: tools/theme_mock.py)

/// A key class's material, drawn over its fill and clipped to the key.
struct ThemeFace: Equatable {
    /// A tile in GlyfKeyboard/Textures (<name>.png, grey + alpha), laid over
    /// the fill at `textureAlpha`, one image pixel to one screen pixel.
    let texture: String?
    let textureAlpha: Double
    /// White at the top at `sheenTop`, fading out by the middle; black at
    /// the bottom at `sheenBottom`, fading in from the middle.
    let sheenTop: Double
    let sheenBottom: Double
    /// A one-pixel white line along the inside top edge, at this alpha.
    let highlight: Double
    /// Lacquer: white over the top 48% fading to clear.
    let gloss: Double
    /// Brushed metal: three soft horizontal light bands.
    let metal: Double
    /// A second fill: the face runs fill -> fill2 diagonally.
    let fill2: UInt32?
    /// A typewriter's round keycap, its diameter the key's width, centred in
    /// the key's own cell (which never changes), in a chrome `ring`.
    let round: Bool
    let ring: UInt32?
}

struct ThemeFaces {
    let letter: ThemeFace
    let function: ThemeFace
    let space: ThemeFace
    let ret: ThemeFace
}

enum ThemeLegendStyle { case ink, engraved, letterpress, foil, glow }

/// How the letters and glyphs sit on the key. `foil` is top, middle and
/// bottom of the leaf's gradient (empty for every other style).
struct ThemeLegend {
    let style: ThemeLegendStyle
    let foil: [UInt32]
}

/// The keys an ornament goes on. `function` is every function key but
/// return (shift and delete included).
enum ThemeOrnamentTarget: String { case letter, function, space, ret, shift, delete }

/// Where an ornament's x = 0 sits: the key's left edge, centre or right edge.
enum ThemeAnchor { case left, center, right }

/// An ornament's colour: one of the variant's own, the key's fill, or a hex.
enum ThemeColorRole: Equatable { case ink, fnInk, accent, accentInk, fill, hex(UInt32) }

enum ThemeOrnamentFont { case system, mono, theme }

/// One vector primitive, every number in units of the key's height,
/// x from the anchor and y from the key's top. A colour of its own wins
/// over the ornament's.
enum ThemeOrnamentOp {
    case line(Double, Double, Double, Double, w: Double, color: ThemeColorRole? = nil)
    /// A closed, filled polygon: x0, y0, x1, y1, ...
    case poly([Double], color: ThemeColorRole? = nil)
    /// cx, cy, r: filled, or stroked `w` wide.
    case circle(Double, Double, Double, w: Double? = nil, color: ThemeColorRole? = nil)
    /// x, y, width, height, corner radius: filled, or stroked `w` wide.
    case rect(Double, Double, Double, Double, Double, w: Double? = nil, color: ThemeColorRole? = nil)
    /// A string centred on (x, y).
    case text(String, Double, Double, size: Double, font: ThemeOrnamentFont, weight: Int, tracking: Double,
              color: ThemeColorRole? = nil)

    var color: ThemeColorRole? {
        switch self {
        case .line(_, _, _, _, _, let c), .poly(_, let c), .circle(_, _, _, _, let c),
             .rect(_, _, _, _, _, _, let c), .text(_, _, _, _, _, _, _, let c): return c
        }
    }
}

/// A theme's signature detail on the keys it names.
struct ThemeOrnament {
    let on: ThemeOrnamentTarget
    let anchor: ThemeAnchor
    let color: ThemeColorRole
    let alpha: Double
    let ops: [ThemeOrnamentOp]
}

struct ThemeStyle {
    let faces: ThemeFaces
    let legend: ThemeLegend
    /// Return's own: engraved ink, never the theme's foil or glow (gold on
    /// a gold return lost the arrow).
    let returnLegend: ThemeLegend
    let ornaments: [ThemeOrnament]
}

/// A key-face font shipped in the keyboard's bundle (GlyfKeyboard/Fonts).
struct ThemeFont {
    let family: String
    /// Resource name and extension in the bundle.
    let file: String
    let ext: String
    let weight: Int
    /// A variable file kept whole (its licence reserves the name): the
    /// weight is asked for at run time.
    let variable: Bool
}

/// Shift, delete, return, globe and emoji symbols: today's weight, or one
/// step lighter or heavier (§5.4). Never their size.
enum ThemeGlyphStyle { case standard, light, bold }

/// What a key press sounds like in a pack.
enum ThemeSoundRole: Hashable { case letter, space, delete, ret }

/// A theme's sound pack: the roles it has a sample of its own for, as
/// GlyfKeyboard/Sounds/theme-<name>-<role>.caf.
struct ThemeSoundPack { let name: String; let roles: [ThemeSoundRole] }

/// The one texture iOS draws on keys: Marble's veins, or Rose Gold's satin
/// sheen on its function keys (a gradient, not a picture).
struct ThemeTexture {
    enum Kind { case veins, satin }
    let kind: Kind
    let amplitude: Double
}

struct KeyboardTheme {
    let id: String
    let name: String
    /// nil keeps the system face.
    let font: ThemeFont?
    let glyphStyle: ThemeGlyphStyle
    let sound: ThemeSoundPack
    let keyTexture: ThemeTexture?
    let light: ThemeVariant
    let dark: ThemeVariant

    func variant(dark isDark: Bool) -> ThemeVariant { isDark ? dark : light }

    /// The theme a saved `skin` names; nil for "", nil or an id this build
    /// doesn't know (a downgrade, or a theme removed later): today's look.
    static func named(_ id: String?) -> KeyboardTheme? {
        guard let id, !id.isEmpty else { return nil }
        return all.first { $0.id == id }
    }
}

extension UIColor {
    /// 0xRRGGBB → colour.
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - Fonts (registered lazily, one theme's at a time — §4.1)

private final class ThemeBundleToken {}

enum ThemeFonts {
    /// Where the font files are; nil reads the keyboard's own bundle. Tests
    /// point it at the source folder.
    static var directory: URL?

    private static var active: (font: ThemeFont, url: URL, postScript: String)?
    private static var cache: [CGFloat: UIFont] = [:]

    static func url(for font: ThemeFont) -> URL? {
        if let directory { return directory.appendingPathComponent(font.file + "." + font.ext) }
        return Bundle(for: ThemeBundleToken.self).url(forResource: font.file, withExtension: font.ext)
    }

    /// Makes `font` the one key face: registers its file for this process
    /// the first time, and lets the previous theme's go, so only the active
    /// theme's font is resident. nil goes back to the system face.
    static func activate(_ font: ThemeFont?) {
        if let a = active, let font, a.font.file == font.file { return }
        if let a = active {
            CTFontManagerUnregisterFontsForURL(a.url as CFURL, .process, nil)
            active = nil
        }
        cache = [:]
        guard let font, let url = url(for: font) else { return }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? 0
            // Already registered (a reload of the extension) is fine.
            guard code == CTFontManagerError.alreadyRegistered.rawValue else { return }
        }
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descs.first,
              let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
        else { return }
        active = (font, url, name)
    }

    /// The active theme's face at `size` (today's point size, never another),
    /// or nil to use the system face.
    static func font(size: CGFloat) -> UIFont? {
        guard let a = active else { return nil }
        if let f = cache[size] { return f }
        var desc = UIFontDescriptor(name: a.postScript, size: size)
        if a.font.variable {
            // 'wght' as a four-character code.
            let wght = 0x7767_6874
            desc = desc.addingAttributes([
                UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String):
                    [wght: a.font.weight],
            ])
        }
        let f = UIFont(descriptor: desc, size: size)
        // UIFont never fails here: a missing face comes back as the system
        // one, which is the fallback the spec asks for anyway.
        cache[size] = f
        return f
    }

    static var activePostScriptName: String? { active?.postScript }
}

// MARK: - Sounds (§4.3)

/// A theme's key sounds as system sounds: made once when the theme loads,
/// let go when it changes. They play through the ring/silent switch rule
/// like every system sound. Anything that cannot play (no pack, no Full
/// Access, theme sounds off, a file that failed to load) leaves the system
/// click to the caller.
final class ThemeSound {
    static let shared = ThemeSound()

    private var ids: [ThemeSoundRole: SystemSoundID] = [:]
    private(set) var packName = "system"
    /// The person's "theme sounds" switch, and Full Access (reports say a
    /// keyboard without it plays no audio of its own: docs/THEMES.md §4.1).
    var allowed = true

    /// Loads `pack`'s samples, disposing of the last pack's.
    func load(_ pack: ThemeSoundPack?) {
        let name = pack?.name ?? "system"
        guard name != packName else { return }
        for id in ids.values { AudioServicesDisposeSystemSoundID(id) }
        ids = [:]
        packName = name
        guard let pack else { return }
        let bundle = Bundle(for: ThemeBundleToken.self)
        for role in pack.roles {
            guard let url = bundle.url(forResource: "theme-\(pack.name)-\(Self.fileRole(role))",
                                       withExtension: "caf") else { continue }
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError {
                ids[role] = id
            }
        }
        #if DEBUG
        NSLog("GLYF_THEME_SOUND pack=%@ loaded=%d of %d allowed=%d", pack.name, ids.count, pack.roles.count, allowed ? 1 : 0)
        #endif
    }

    private static func fileRole(_ role: ThemeSoundRole) -> String {
        switch role {
        case .letter: return "letter"
        case .space: return "space"
        case .delete: return "delete"
        case .ret: return "return"
        }
    }

    /// The sample a role plays: its own, else the letter's. nil means the
    /// system click.
    func sample(for role: ThemeSoundRole) -> SystemSoundID? {
        guard allowed else { return nil }
        return ids[role] ?? ids[.letter]
    }

    /// Plays the role's sample; false when the caller should click instead.
    @discardableResult
    func play(_ role: ThemeSoundRole) -> Bool {
        guard let id = sample(for: role) else { return false }
        AudioServicesPlaySystemSound(id)
        return true
    }
}

// MARK: - Key textures (Marble's veins, one shared tile — §4.1)

enum ThemeTextures {
    private static var tile: (ink: UInt32, alpha: Double, color: UIColor)?

    /// The vein tile as a pattern colour: 256 px square, seamless, thin
    /// meandering lines in the ink colour at `alpha` (≤ 3%). One tile for
    /// every key; never a bitmap per key.
    static func veins(ink: UInt32, alpha: Double) -> UIColor {
        if let t = tile, t.ink == ink, t.alpha == alpha { return t.color }
        let side = 256
        var px = [UInt8](repeating: 0, count: side * side * 4)
        let r = UInt8((ink >> 16) & 0xFF), g = UInt8((ink >> 8) & 0xFF), b = UInt8(ink & 0xFF)
        for y in 0..<side {
            for x in 0..<side {
                let t = abs(sin(2 * .pi * Double(x) / Double(side) + 6 * fbm(Double(x), Double(y), period: side)))
                // Thin lines where the turbulence crosses zero.
                let line = max(0, 1 - t / 0.06)
                guard line > 0 else { continue }
                let a = line * alpha
                let i = (y * side + x) * 4
                // Premultiplied RGBA.
                px[i] = UInt8(Double(r) * a); px[i + 1] = UInt8(Double(g) * a)
                px[i + 2] = UInt8(Double(b) * a); px[i + 3] = UInt8(255 * a)
            }
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let color: UIColor
        if let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                               space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
           let image = ctx.makeImage() {
            color = UIColor(patternImage: UIImage(cgImage: image, scale: 2, orientation: .up))
        } else {
            color = .clear
        }
        tile = (ink, alpha, color)
        return color
    }

    static func release() { tile = nil }

    /// Periodic value noise, four octaves, wrapping at `period` pixels.
    private static func fbm(_ x: Double, _ y: Double, period: Int) -> Double {
        var sum = 0.0, amp = 0.5, cells = 4
        for _ in 0..<4 {
            sum += amp * valueNoise(x * Double(cells) / Double(period), y * Double(cells) / Double(period), wrap: cells)
            amp *= 0.5
            cells *= 2
        }
        return sum
    }

    private static func valueNoise(_ x: Double, _ y: Double, wrap: Int) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        func h(_ i: Int, _ j: Int) -> Double {
            let a = ((i % wrap) + wrap) % wrap, b = ((j % wrap) + wrap) % wrap
            var n = UInt32(truncatingIfNeeded: a &* 374_761_393 &+ b &* 668_265_263 &+ wrap &* 2_147_483)
            n = (n ^ (n >> 13)) &* 1_274_126_177
            return Double(n ^ (n >> 16)) / Double(UInt32.max)
        }
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let top = h(xi, yi) + (h(xi + 1, yi) - h(xi, yi)) * sx
        let bottom = h(xi, yi + 1) + (h(xi + 1, yi + 1) - h(xi, yi + 1)) * sx
        return top + (bottom - top) * sy
    }

    /// Rose Gold's satin: the fill 4% lighter at the top and 4% darker at the
    /// bottom, in HSL lightness (§6, theme 11), with the glyph checked at
    /// both ends. An end that would take the glyph under 4.5:1 stops short
    /// where it still clears it (the dark variant's bottom: -4% read 4.04:1,
    /// so it ends at -0.5%).
    static func satin(_ rgb: UInt32, glyph: UInt32) -> [CGColor] {
        if let c = satinCache, c.fill == rgb, c.glyph == glyph { return c.colors }
        func end(_ delta: Double) -> UIColor {
            var d = delta
            while abs(d) > 0.0001 {
                let c = shiftLightness(rgb, d)
                if contrast(c, UIColor(rgb: glyph)) >= 4.5 { return c }
                d -= 0.005 * (d > 0 ? 1 : -1)
            }
            return UIColor(rgb: rgb)
        }
        let colors = [end(0.04).cgColor, end(-0.04).cgColor]
        satinCache = (rgb, glyph, colors)
        return colors
    }
    private static var satinCache: (fill: UInt32, glyph: UInt32, colors: [CGColor])?

    /// WCAG 2.x contrast ratio.
    static func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        func lum(_ c: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, al: CGFloat = 0
            c.getRed(&r, green: &g, blue: &bl, alpha: &al)
            let f = { (v: Double) in v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * f(Double(r)) + 0.7152 * f(Double(g)) + 0.0722 * f(Double(bl))
        }
        let x = lum(a), y = lum(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    static func shiftLightness(_ rgb: UInt32, _ delta: Double) -> UIColor {
        let r = Double((rgb >> 16) & 0xFF) / 255, g = Double((rgb >> 8) & 0xFF) / 255, b = Double(rgb & 0xFF) / 255
        let hi = max(r, g, b), lo = min(r, g, b)
        var h = 0.0, s = 0.0
        let l = (hi + lo) / 2
        if hi != lo {
            let d = hi - lo
            s = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo)
            if hi == r { h = (g - b) / d + (g < b ? 6 : 0) } else if hi == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
            h /= 6
        }
        let l2 = min(1, max(0, l + delta))
        func hue(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        guard s > 0 else { return UIColor(red: l2, green: l2, blue: l2, alpha: 1) }
        let q = l2 < 0.5 ? l2 * (1 + s) : l2 + s - l2 * s
        let p = 2 * l2 - q
        return UIColor(red: hue(p, q, h + 1 / 3), green: hue(p, q, h), blue: hue(p, q, h - 1 / 3), alpha: 1)
    }
}
