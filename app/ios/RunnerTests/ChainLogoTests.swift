import XCTest
@testable import Runner

/// The chains' marks (ChainLogo): every chain the trade panel offers has
/// one, its vector paths parse inside the mark's own box, and it renders.
final class ChainLogoTests: XCTestCase {

    func testEveryTradeChainHasAMark() {
        for chain in SponsorMenu.swapChains + TradeEdit.flashChains {
            XCTAssertNotNil(ChainLogo.mark(chain), chain)
        }
        XCTAssertNotNil(ChainLogo.mark("op"))
        XCTAssertNil(ChainLogo.mark("whitechain-sepolia"))
    }

    func testPathsFillTheirViewBox() {
        for (chain, mark) in ChainLogo.marks where mark.lettering == nil {
            let box = mark.layers.map { SVGPath.parse($0.d).boundingBoxOfPath }.reduce(CGRect.null) { $0.union($1) }
            XCTAssertFalse(box.isEmpty, chain)
            let view = CGRect(origin: .zero, size: mark.viewBox).insetBy(dx: -mark.viewBox.width * 0.1, dy: -mark.viewBox.height * 0.1)
            XCTAssertTrue(view.contains(box), "\(chain): \(box) outside \(mark.viewBox)")
            // A mark that came out tiny would mean the parser dropped most of it.
            XCTAssertGreaterThan(box.width, mark.viewBox.width * 0.5, chain)
            XCTAssertGreaterThan(box.height, mark.viewBox.height * 0.5, chain)
        }
    }

    func testTheParserReadsRelativeAndRepeatedCommands() {
        // Base's square: c, h and v, relative, with arguments run together.
        let base = SVGPath.parse(ChainLogo.marks["base"]!.layers[0].d).boundingBoxOfPath
        XCTAssertEqual(base.minX, 0, accuracy: 0.5)
        XCTAssertEqual(base.maxX, 1280, accuracy: 0.5)
        XCTAssertEqual(base.maxY, 1280, accuracy: 0.5)
        let square = SVGPath.parse("M0,0h10v10h-10z").boundingBoxOfPath
        XCTAssertEqual(square, CGRect(x: 0, y: 0, width: 10, height: 10))
        let numbers = SVGPath.parse("M0 0L5-5 10.5.5").boundingBoxOfPath
        XCTAssertEqual(numbers.minY, -5)
        XCTAssertEqual(numbers.maxX, 10.5)
    }

    func testMarksRenderAtTheSizeAsked() {
        for chain in ["base", "ethereum", "arbitrum", "optimism", "unichain", "solana"] {
            let img = ChainLogo.image(chain, side: 28)
            XCTAssertEqual(img?.size, CGSize(width: 28, height: 28), chain)
        }
    }
}
