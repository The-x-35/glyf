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

/// The emoji board, laid out like Apple's. Since iOS 18.1 an iPhone's emoji
/// keyboard shows FOUR rows of bigger emoji where it used to show five
/// (Arpit's iPhone 16 Pro on iOS 18.7, 2026-11-04: "normal iOS uses only 4
/// rows"). The iOS 26.5 simulator still draws the older five-row board, so
/// the five-row numbers below are what was measured there (Messages, 402pt,
/// @3x, ink not boxes) and the four rows are the same board with each row
/// grown to a quarter of the grid, glyph and column pitch keeping Apple's
/// proportions:
///
///     Apple, 5 rows (sim)   row 38.4  column 46.0  glyph ink 29.3  first glyph x 15.3
///     Glyf, 4 rows (402)    row 47.5  column 56.9  glyph ink 36.2  first glyph x 15.3
///
/// The chrome is Apple's own: a 40pt search field 9pt in from the edges,
/// the section name 13.7pt under it in a lighter grey, nine category glyphs
/// 33.2pt apart starting at 51.3, delete 21.3 x 17.7pt of ink. Search keeps
/// the board's height (Apple's does) with one row of 34.7pt emoji 53pt apart.
enum EmojiMetrics {
    /// Rows in the grid. Apple's iPhone board since iOS 18.1.
    static let rows = 4

    /// Apple's five-row grid, measured on the iOS 26.5 simulator.
    static let appleRowPitch: CGFloat = 38.4
    static let appleColumnPitch: CGFloat = 46.0
    static let appleGlyphInk: CGFloat = 29.3
    /// Apple Color Emoji's ink per point of font size (a 32pt face draws a
    /// 29.7pt face), so a wanted ink size gives the font size.
    static let inkPerPoint: CGFloat = 0.928

    /// The board's own height over the letters: unchanged (the keyboard
    /// never changes height for emoji beyond what it always has).
    static let extraHeight: CGFloat = 44

    // Chrome, in the board's own coordinates.
    static let fieldTop: CGFloat = 4
    static let fieldHeight: CGFloat = 40
    static let fieldInset: CGFloat = 9
    /// The section name's frame; its capitals start 3.7pt lower, 13.7pt
    /// under the field, as on Apple's.
    static let labelTop: CGFloat = 54
    static let labelX: CGFloat = 12
    /// The grid's band: 6.6pt under the section name's capitals, ending
    /// 21.4pt above the category glyphs' middle.
    static let gridTop: CGFloat = 73.5
    static let gridBottomInset: CGFloat = 41.5
    /// The category bar: 34pt tall, its middle 20pt off the board's bottom.
    static let barHeight: CGFloat = 34
    static let barBottomInset: CGFloat = 37
    static let barX: CGFloat = 51.3
    static let barTrailing: CGFloat = 51.9
    static let barCount: CGFloat = 9
    /// The first glyph's left edge, which Apple lines up with the section name.
    static let glyphLeft: CGFloat = 15.3

    /// One row of the grid for a board this tall, on a half point.
    static func rowPitch(boardHeight h: CGFloat) -> CGFloat {
        floor((h - gridBottomInset - gridTop) / CGFloat(rows) * 2) / 2
    }
    static func columnPitch(rowPitch r: CGFloat) -> CGFloat {
        (r * appleColumnPitch / appleRowPitch * 10).rounded() / 10
    }
    static func glyphInk(rowPitch r: CGFloat) -> CGFloat { r * appleGlyphInk / appleRowPitch }
    static func glyphFont(rowPitch r: CGFloat) -> CGFloat {
        (glyphInk(rowPitch: r) / inkPerPoint * 2).rounded() / 2
    }
    /// Where the first column's cell starts so its glyph lands on glyphLeft.
    static func gridX(rowPitch r: CGFloat) -> CGFloat {
        glyphLeft - (columnPitch(rowPitch: r) - glyphInk(rowPitch: r)) / 2
    }
    /// The board on a phone this wide: strip + keys + extraHeight.
    static func boardHeight(width: CGFloat) -> CGFloat {
        Glass.toolbarHeight + KeyMetrics.keysHeight(width: width) + extraHeight
    }

    // Search: the field and one row of results over the letter keys, the
    // whole keyboard as tall as the board (no jump), the keys where they
    // always are.
    static func searchStripHeight() -> CGFloat { Glass.toolbarHeight + extraHeight }
    static let searchFieldTop: CGFloat = 4
    static let searchFieldHeight: CGFloat = 36
    static let searchRowTop: CGFloat = 44
    static let searchPitch: CGFloat = 53
    static let searchGlyphInk: CGFloat = 34.7
    static var searchGlyphFont: CGFloat { (searchGlyphInk / inkPerPoint * 2).rounded() / 2 }
    static let searchGlyphLeft: CGFloat = 11.7
}

enum Glass {

    /// Resolved by the keyboard VC from settings + host appearance.
    static var isDark = false
    /// Key style, user-picked in the app: "site" (default, Apple's iOS 26
    /// keys on the system sheet) or "glass" (translucent keys). Older
    /// installs may still carry "classic" or "glow".
    static var keyTheme = "site"

    /// The keyboard theme picked in the app (settings `skin`, one of the 24
    /// in docs/THEMES.md), or nil for today's look. A theme colours the keys,
    /// glyphs, press popup, chip, dot, shadows and borders, and sets the key
    /// face and sound; it never paints a board and never changes a size
    /// (§0). Its variant follows the host's appearance, as `isDark` does.
    static var skin: KeyboardTheme?
    /// The skin's variant for the sheet of the moment.
    static var skinVariant: ThemeVariant? { skin?.variant(dark: isDark) }

    /// True while the keyboard wears the default look (no theme picked).
    static var siteLook: Bool { keyTheme == "site" && !themedBgActive && skin == nil }

    /// The website's structure (flat cards, no surface headers): the default
    /// look and every colour theme.
    static var solidLook: Bool { keyTheme == "site" || themedBgActive || skin != nil }

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

    /// The board a colour or gradient theme paints, with the dim applied;
    /// empty with no theme. The VC lays it under the keys (see
    /// applyBoardPaint), which is what the app's Look tiles show.
    static var boardColors: [UIColor] { themeColors }

    /// The one colour a painted board reads as: the colour, or the middle of
    /// the gradient. Decides whether the keys and the ink go light or dark.
    private static var boardSeed: UIColor? {
        let colors = themeColors
        guard let first = colors.first, let last = colors.last else { return nil }
        return colors.count > 1 ? first.blend(last, 0.5) : first
    }

    /// The app's KeyPalette rule, kept in step: a board brighter than this
    /// carries white keys and dark ink; a darker one lifted keys and white ink.
    static var boardIsLight: Bool { (boardSeed?.glyfLuminance ?? 1) > 0.34 }

    /// Keys used to carry slices of the gradient; now the board carries it
    /// and every key is one colour, as on the tiles. Kept for KeyboardView.
    static var keyGradient: [UIColor]? { nil }

    /// One key's colour: Apple's on the system sheet, or the key the app's
    /// tile draws on this board (white on a light board, the board lifted
    /// towards white on a dark one) — the same numbers as KeyPalette.
    static var keyColor: UIColor {
        guard let seed = boardSeed else {
            return isDark ? appleKeyDark : appleKeyLight
        }
        return boardIsLight ? .white : seed.blend(.white, 0.185)
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

    /// The glass look keeps its translucent keys over the sheet; a theme
    /// brings its own opaque keys.
    private static var glassKeys: Bool { keyTheme == "glass" && !themedBgActive && skin == nil }

    /// Glyphs on keys: whichever of black and white the key can carry.
    static var keyInk: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.keyText) }
        if glassKeys { return textPrimary }
        return keyColor.glyfLuminance > 0.5 ? .black : .white
    }

    /// Glyphs on function keys (shift, delete, 123, emoji, globe, a plain
    /// return): the theme's function glyph, else the keys' ink.
    static var fnInk: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.functionGlyph) }
        return keyInk
    }

    /// The dot on a bound key is the brand purple, unless the key is a
    /// colour purple disappears into; then it takes the glyph ink.
    static var boundDot: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.boundDot) }
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

    /// Apple's sheet, for the one case we paint it: a forced light or dark
    /// on a host whose own sheet is the other way. Measured off iOS 26.
    static func sheetPaint(dark: Bool) -> UIColor {
        dark ? UIColor(white: 0.16, alpha: 1)
             : UIColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 1)
    }
    /// Chrome (the strip, panels, hairlines) sits on whatever is behind it:
    /// the system sheet, or a painted board, whose brightness decides.
    static var chromeDark: Bool { themedBgActive ? !boardIsLight : isDark }

    /// The key grid's own background. NOT `.clear`, and not for looks.
    ///
    /// A KEYBOARD EXTENSION discards a touch that lands on a fully
    /// transparent pixel before hitTest ever runs — unlike an ordinary app,
    /// where only the view's alpha matters. A clear grid left every gap
    /// between keys dead at the window: no hitTest, no touchesBegan, no
    /// press, and the nearest-key rule never got a say.
    ///
    /// One part in 255 is invisible over the system sheet and over any theme
    /// background, and is enough to make the whole area touchable. It
    /// follows the appearance so it can never tint a dark or themed board.
    static var touchableGrid: UIColor {
        (chromeDark ? UIColor.black : UIColor.white).withAlphaComponent(0.01)
    }

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
        if let v = skinVariant { return UIColor(rgb: v.letter.fill) }
        if keyGradient != nil { return .clear }   // KeyboardView paints the slice
        if glassKeys {
            return isDark ? UIColor.white.withAlphaComponent(0.14)
                          : UIColor.white.withAlphaComponent(0.58)
        }
        if isDark, boardSeed == nil { return appleKeyDarkWash }
        return keyColor
    }
    /// Apple's dark keys are white laid over the sheet, not a grey of their
    /// own: #404041 on the usual dark sheet (27), a step above it wherever
    /// iOS draws the sheet lighter. Safari with a light page in dark mode
    /// draws it at 66, where Apple's keys read 96 and an opaque #404041 sank
    /// into it, the keys gone (measured on the iOS 26.5 sim, 2026-10-14).
    private static let appleKeyDarkWash = UIColor.white.withAlphaComponent(0.159)
    static var fillKeyPressed: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.letter.pressed) }
        if keyGradient != nil { return UIColor.white.withAlphaComponent(0.28) }
        if glassKeys {
            return isDark ? UIColor.white.withAlphaComponent(0.40)
                          : UIColor.white.withAlphaComponent(0.92)
        }
        // The same step as below (64 → 91 on the usual sheet), as a wash.
        if isDark, boardSeed == nil { return UIColor.white.withAlphaComponent(0.28) }
        if let seed = boardSeed {
            return boardIsLight ? keyColor.blend(seed, 0.55) : keyColor.blend(.white, 0.11)
        }
        return keyColor.blend(keyInk, 0.14)
    }
    /// Solid version regardless of theme (press balloons): a theme's press
    /// popup colour.
    static var fillKeySolid: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.popupFill) }
        return keyColor
    }
    /// The letter in the press balloon and the glide's floating word: a
    /// theme's popup ink, else the keys' ink.
    static var popupInk: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.popupText) }
        return keyInk
    }
    /// The space bar: the letter colour today; a theme may give it its own.
    static var fillKeySpace: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.space.fill) }
        return fillKey
    }
    static var fillKeySpacePressed: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.space.pressed) }
        return fillKeyPressed
    }
    /// Function keys (shift, delete, 123, emoji, return) wear the letter
    /// colour, as they do on iOS 26; on a painted board they take the tile's
    /// darker (or lighter) function-key shade. On a dark board that shade
    /// is lifted 12%, which puts it where Apple's own dark keys sit against
    /// their sheet: a step below the letters, never sunk into the board.
    static var fillKeyFn: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.function.fill) }
        guard let seed = boardSeed else { return fillKey }
        return boardIsLight ? seed.blend(.black, 0.14) : seed.blend(.white, 0.12)
    }
    static var fillKeyFnPressed: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.function.pressed) }
        return fillKeyPressed
    }
    /// A theme's own colours for shift or delete (Primary's), or nil.
    static func keyOverride(shift: Bool) -> ThemeOverride? {
        shift ? skinVariant?.shift : skinVariant?.delete
    }
    /// The on state of the keyboard's own switches and segments: ink in
    /// light, as in the app; in dark, a light track the white thumb still
    /// stands out on.
    static var controlOn: UIColor {
        isDark ? UIColor(white: 0.86, alpha: 1)
               : UIColor(red: 0x17 / 255, green: 0x18 / 255, blue: 0x1C / 255, alpha: 1)
    }
    /// A switch's on track: ink in light (the app's), iOS's green in dark,
    /// where a light track under the white thumb read the same as off.
    static var switchOn: UIColor {
        isDark ? UIColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
               : UIColor(red: 0x17 / 255, green: 0x18 / 255, blue: 0x1C / 255, alpha: 1)
    }
    /// Text on `controlOn` (a selected segment's title).
    static var controlOnText: UIColor {
        isDark ? UIColor(red: 0x17 / 255, green: 0x18 / 255, blue: 0x1C / 255, alpha: 1) : .white
    }

    /// Apple's blue return key for go, search, send and done: #007AFF,
    /// measured on the iOS 26.5 simulator; the dark twin is iOS's dark blue.
    /// A theme's return colour replaces the blue only while the theme is on.
    static var returnBlue: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.returnFill) }
        return isDark ? UIColor(red: 10 / 255, green: 132 / 255, blue: 1, alpha: 1)
                      : UIColor(red: 0, green: 122 / 255, blue: 1, alpha: 1)
    }
    static var returnBluePressed: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.returnPressed) }
        return returnBlue.blend(.black, 0.18)
    }
    /// The glyph or word on the blue (or the theme's) return.
    static var returnInk: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.returnText) }
        return .white
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
        chromeDark ? UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
                   : UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1)
    }
    /// Cards INSIDE keyboard surfaces (clips, tiles, results): Apple's key
    /// colour, so they read as part of the same keyboard on either sheet; on
    /// a painted board, the board's own key colour.
    static var surfaceCard: UIColor {
        if themedBgActive { return keyColor }
        return isDark ? appleKeyDark : appleKeyLight
    }
    /// A tile or a row laid straight on the sheet (the menu's tools, the
    /// vault's details): in dark, the keys' wash, so it stands off the sheet
    /// wherever iOS draws it (opaque #404041 vanished on Safari's lighter
    /// sheet, 2026-10-14). Popups and overlays keep the opaque card.
    static var surfaceTile: UIColor {
        if isDark, !themedBgActive { return appleKeyDarkWash }
        return surfaceCard
    }
    /// Soft chip/field fill over the sheet (the web's --kb-soft).
    static var fillSoft: UIColor {
        chromeDark ? UIColor.white.withAlphaComponent(0.08) : UIColor.white.withAlphaComponent(0.6)
    }
    /// Dims a panel behind a menu, over whatever the sheet is.
    static var scrim: UIColor {
        chromeDark ? UIColor.black.withAlphaComponent(0.55) : UIColor.white.withAlphaComponent(0.62)
    }

    // MARK: Strokes

    static var strokeHairline: UIColor {
        chromeDark ? UIColor.white.withAlphaComponent(0.10)
                   : UIColor.black.withAlphaComponent(0.08)
    }
    /// The line between two rows of a grouped list: Settings draws its own
    /// at about a sixth of black, firmer than the hairline around a card.
    static var strokeSeparator: UIColor {
        chromeDark ? UIColor.white.withAlphaComponent(0.14)
                   : UIColor.black.withAlphaComponent(0.16)
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
    /// Purple words and marks on a strip chip ("Insert", sparkles, the
    /// clipboard mark): lighter than the accent, which read as unreadable
    /// there (Arpit, 2026-09-30). Semibold, each is over 3:1 on its chip:
    /// 3.7 on white, 5.6 on the dark key colour.
    static var chipAccent: UIColor {
        if let v = skinVariant { return UIColor(rgb: v.chipAccent) }
        return chromeDark ? UIColor(red: 0xC3 / 255, green: 0xB4 / 255, blue: 0xFF / 255, alpha: 1)
                          : UIColor(red: 0x8A / 255, green: 0x6C / 255, blue: 0xFF / 255, alpha: 1)
    }
    /// A theme's chip face (opaque), or nil for the glass face over the sheet.
    static var chipFace: UIColor? { skinVariant.map { UIColor(rgb: $0.chipFace) } }
    /// Whether the chip's face is dark: the sheet's, or a theme face's own
    /// (Rangefinder's light variant puts a black chip on the light sheet).
    static var chipFaceDark: Bool { chipFace.map { $0.glyfLuminance < 0.5 } ?? chromeDark }
    /// Words on the chip, read against its face.
    static var chipText: UIColor {
        guard skin != nil else { return textPrimary }
        return chipFaceDark ? .white : UIColor(white: 0.07, alpha: 1)
    }
    static var chipTextSecondary: UIColor {
        guard skin != nil else { return textSecondary }
        return chipFaceDark ? UIColor(white: 0.63, alpha: 1) : UIColor(white: 0.42, alpha: 1)
    }
    /// iMessage blue — the website's send/Replace colour.
    static let imBlue = UIColor(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255, alpha: 1)
    static let accentSuccess = UIColor(red: 0x32 / 255, green: 0xD5 / 255, blue: 0x83 / 255, alpha: 1)
    static let accentWarning = UIColor(red: 0xB7 / 255, green: 0x79 / 255, blue: 0x09 / 255, alpha: 1)
    static let accentDanger = UIColor(red: 0xF0 / 255, green: 0x44 / 255, blue: 0x38 / 255, alpha: 1)

    /// Text on the sheet and on cards. Glyphs on keys use `keyInk`, which
    /// follows the key colour instead.
    static var textPrimary: UIColor {
        chromeDark ? .white : UIColor(white: 0.07, alpha: 1)
    }
    static var textSecondary: UIColor {
        chromeDark ? UIColor(white: 0.63, alpha: 1) : UIColor(white: 0.42, alpha: 1)
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

    /// The shadow under a KEY (the cards and tiles in panels keep the plain
    /// keyShadow* above): a theme's 1pt edge or its glow, else today's. A
    /// glow is drawn only with Reduce Transparency and Reduce Motion both
    /// off (§4.1); the edge always.
    static var keyFaceShadow: (color: UIColor, opacity: Float, offset: CGSize, radius: CGFloat) {
        guard let s = skinVariant?.shadow else {
            return (keyShadowColor, keyShadowOpacity, keyShadowOffset, keyShadowRadius)
        }
        let glow = s.radius > 0
        let opacity: Float = glow && (reduceTransparency || reduceMotion) ? 0 : Float(s.alpha)
        return (UIColor(rgb: s.color), opacity, CGSize(width: 0, height: s.offsetY), CGFloat(s.radius))
    }

    /// A theme's border for a key class: always drawn when the theme has
    /// one (the "borders around keys" switch then has no say), nil
    /// otherwise.
    static func skinBorder(for cls: ThemeKeyClass) -> (color: UIColor, width: CGFloat)? {
        guard let b = skinVariant?.border else { return nil }
        return b.appliesTo.contains(cls) ? (UIColor(rgb: b.color), CGFloat(b.width)) : (.clear, 0)
    }

    // MARK: Key face type and symbols

    /// The key-face font at TODAY's point size: a theme's face, else the
    /// system's. Never a different size (§0.2).
    static func keyFont(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        if skin?.font != nil, let f = ThemeFonts.font(size: size) { return f }
        return .systemFont(ofSize: size, weight: weight)
    }

    /// A symbol's weight on a key: today's, or the theme's glyph style
    /// (light, or semibold for bold). The point size never changes (§5.4).
    static func glyphWeight(_ today: UIImage.SymbolWeight) -> UIImage.SymbolWeight {
        switch skin?.glyphStyle ?? .standard {
        case .standard: return today
        case .light: return .light
        case .bold: return .semibold
        }
    }

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

    /// The strip is Apple's predictive bar: 45pt, so with the keys' 6pt
    /// top gap the first row sits 51pt under the keyboard's top edge, where
    /// Apple's does. iOS 26 sometimes draws a 16pt band of its own sheet
    /// above a third-party keyboard (Messages) and often doesn't (Safari's
    /// forms, and no older iOS does), so nothing counts on it (Arpit,
    /// 2026-10-06: "the top pannel feels cut in safari", "think like mostly
    /// you wont have the 16 pt gap, i need you to keep it same to apple
    /// keyboard"). The chip needs 38pt with room for its glow (2026-09-30:
    /// "text seems too close to border"). The same with a chip or without,
    /// so nothing jumps when one comes or goes, and the keys are
    /// bottom-anchored, so none of them move.
    static let stripContent: CGFloat = 45
    /// Nothing of our own above the strip any more: the band is iOS's to
    /// draw or not.
    static let stripBand: CGFloat = 0
    static var toolbarHeight: CGFloat { stripContent + stripBand }
    /// The strip's contents sit where Apple's suggestions do: measured in a
    /// Safari form on iOS 26.5 (2026-10-06), the sheet's edge at 540.0pt,
    /// the suggestion text's middle at 563.7 and the first row at 591.0. So
    /// 24pt under the top edge, 1.5pt under the middle of the strip's box.
    static let stripLift: CGFloat = -1.5

    /// A control centred on the strip's lifted middle, kept inside the view.
    /// The lift puts a full-height control a few points ABOVE the keyboard's
    /// top edge, and iOS cannot place an element that starts outside its
    /// view: VoiceOver and UI tests got it at the top of the screen and could
    /// not press it (the g button, the suggestion card, Close). So a box that
    /// would poke above the top is trimmed evenly top and bottom instead: the
    /// centre, which is what the eye reads, does not move.
    static func stripBox(height: CGFloat, mid: CGFloat) -> (y: CGFloat, height: CGFloat) {
        let top = mid - height / 2
        guard top < 0 else { return (top, height) }
        return (0, max(0, mid * 2))
    }
    static func keysHeight(width: CGFloat) -> CGFloat { KeyMetrics.keysHeight(width: width) }
    static func keyboardBaseHeight(width: CGFloat) -> CGFloat {
        toolbarHeight + keysHeight(width: width)
    }
    /// The number row is one more row of the same pitch (Gboard's and
    /// Apple's own number rows), so turning it on never shrinks a key.
    static func numberRowExtra(width: CGFloat) -> CGFloat { KeyMetrics.rowPitch(width: width) }
    /// An iPhone on its side (compact height): four 40pt rows, as Apple's
    /// keyboard has there, and the number row as one more of them.
    static let sidewaysKeysHeight: CGFloat = 160
    static let sidewaysNumberRowExtra: CGFloat = 40
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
