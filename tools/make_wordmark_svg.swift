// The site's logo: the "glyf" wordmark and its dot as SVG outlines.
//
// Takes Inter's own glyphs at weight 700 and lays them out the way the site's
// CSS sets the wordmark text (letter-spacing -0.045em; a 0.18em dot 0.16em
// after the text, 0.74em above the baseline), so the image is the text,
// sharp at any size. Run from the repo root after changing the wordmark:
//
//     swift tools/make_wordmark_svg.swift
//
// Writes site/public/brand/glyf-wordmark-light.svg and -dark.svg and prints
// the geometry the CSS in site/app/globals.css sizes them by.
import CoreText
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fontURL = root.appendingPathComponent("site/public/fonts/Inter-Variable.ttf")
let em: CGFloat = 1000
let accent = "#7c5cff"
let outputs = [("light", "#1d1d1f"), ("dark", "#f5f5f7")]

guard let base = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor])?.first
else { fatalError("Can't read \(fontURL.path)") }
let bold = CTFontDescriptorCreateCopyWithAttributes(
    base, [kCTFontVariationAttribute: [NSNumber(value: 0x7767_6874 /* wght */): 700]] as CFDictionary)
let font = CTFontCreateWithFontDescriptor(bold, em, nil)

let line = CTLineCreateWithAttributedString(NSAttributedString(string: "glyf", attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTKernAttributeName as String): -0.045 * em,
]))
let letters = CGMutablePath()
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
    for (glyph, at) in zip(glyphs, positions) {
        if let outline = CTFontCreatePathForGlyph(font, glyph, nil) {
            letters.addPath(outline, transform: CGAffineTransform(translationX: at.x, y: at.y))
        }
    }
}

// The dot starts where CSS ends the text: the pen's end, trailing
// letter-spacing included.
let dotSize = 0.18 * em
let dot = CGRect(x: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + 0.16 * em,
                 y: 0.74 * em, width: dotSize, height: dotSize)
let all = CGMutablePath()
all.addPath(letters)
all.addEllipse(in: dot)
let box = all.boundingBoxOfPath

// Cropped to the ink, flipped to SVG's y-down.
func point(_ p: CGPoint) -> String { String(format: "%.1f %.1f", p.x - box.minX, box.maxY - p.y) }
var d = ""
letters.applyWithBlock { element in
    let e = element.pointee
    switch e.type {
    case .moveToPoint: d += "M\(point(e.points[0]))"
    case .addLineToPoint: d += "L\(point(e.points[0]))"
    case .addQuadCurveToPoint: d += "Q\(point(e.points[0])) \(point(e.points[1]))"
    case .addCurveToPoint: d += "C\(point(e.points[0])) \(point(e.points[1])) \(point(e.points[2]))"
    case .closeSubpath: d += "Z"
    @unknown default: break
    }
}
func n(_ v: CGFloat) -> String { String(format: "%.1f", v) }
let size = "viewBox=\"0 0 \(n(box.width)) \(n(box.height))\" width=\"\(n(box.width))\" height=\"\(n(box.height))\""
let circle = "<circle fill=\"\(accent)\" cx=\"\(n(dot.midX - box.minX))\" cy=\"\(n(box.maxY - dot.midY))\" r=\"\(n(dotSize / 2))\"/>"

for (theme, ink) in outputs {
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" \(size) role=\"img\" aria-label=\"Glyf\"><title>Glyf</title>"
        + "<path fill=\"\(ink)\" d=\"\(d)\"/>\(circle)</svg>\n"
    let out = root.appendingPathComponent("site/public/brand/glyf-wordmark-\(theme).svg")
    try svg.write(to: out, atomically: true, encoding: .utf8)
    print("Wrote \(out.path)")
}
print(String(format: "height %.4fem, %.4fem below the baseline, left bearing %.4fem, width %.4fem",
             box.height / em, -box.minY / em, box.minX / em, box.width / em))
