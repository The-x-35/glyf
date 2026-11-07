import CoreText
import UIKit
import UniformTypeIdentifiers

/// A long copied text as a PDF, made on the phone, for apps where a wall of
/// text reads badly (Arpit, 2026-11-07: "if we copied a really big text can
/// we ... convert it to pdf file ... and paste that"). A keyboard can only
/// type text, so the PDF goes on the clipboard and the person pastes it, the
/// way stickers and GIFs already do (MediaClient.copyToPasteboard).
enum TextPDF {
    /// Copies this long offer the PDF button.
    static let minLength = 1_000

    static func offers(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= minLength
    }

    /// US Letter pages, 0.75 inch margins, the system font at 11 pt, as many
    /// pages as the text needs.
    static func make(_ text: String) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let box = page.insetBy(dx: 54, dy: 54)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 6
        let body = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black, .paragraphStyle: style,
        ])
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title(text), kCGPDFContextCreator as String: "Glyf"]
        let setter = CTFramesetterCreateWithAttributedString(body)
        return UIGraphicsPDFRenderer(bounds: page, format: format).pdfData { ctx in
            var at = 0
            let total = body.length
            repeat {
                ctx.beginPage()
                let cg = ctx.cgContext
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: page.height)
                cg.scaleBy(x: 1, y: -1)
                let path = CGPath(rect: CGRect(x: box.minX, y: page.height - box.maxY, width: box.width, height: box.height),
                                  transform: nil)
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: at, length: 0), path, nil)
                CTFrameDraw(frame, cg)
                let shown = CTFrameGetVisibleStringRange(frame).length
                if shown <= 0 { break }
                at += shown
            } while at < total
        }
    }

    /// The document's title: its first line, short.
    static func title(_ text: String) -> String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let t = first.trimmingCharacters(in: .whitespaces)
        return t.count > 60 ? String(t.prefix(57)) + "…" : t
    }

    /// The PDF as the clipboard's one item, so apps paste a document.
    @discardableResult
    static func copy(_ text: String) -> Bool {
        let data = make(text)
        UIPasteboard.general.setItems([[UTType.pdf.identifier: data]], options: [:])
        return UIPasteboard.general.types.contains(UTType.pdf.identifier)
    }
}
