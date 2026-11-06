import XCTest
@testable import Runner

/// The g menu's sponsor row (ETHGlobal Mumbai): which apps show, and what a
/// tap on each puts up.
final class SponsorMenuTests: XCTestCase {

    func testUniswapAndDefinitiveAlwaysShowAndZeroGOnlyWhereTheAppWroteIt() {
        XCTAssertEqual(SponsorMenu.sponsors(privateAI: nil), [.uniswap, .definitive])
        XCTAssertEqual(SponsorMenu.sponsors(privateAI: true), [.uniswap, .definitive, .zeroG])
        // Turned off is still the hackathon build: the icon stays, to turn it on.
        XCTAssertEqual(SponsorMenu.sponsors(privateAI: false), [.uniswap, .definitive, .zeroG])
        XCTAssertEqual(SponsorMenu.Sponsor.allCases.map(\.title), ["Uniswap", "Definitive", "0G"])
    }

    func testUniswapStartsASmallSwapOnBase() throws {
        guard case .trade(let t) = SponsorMenu.action(for: .uniswap, typed: "", privateAI: nil) else {
            return XCTFail("Uniswap should open the trade panel")
        }
        XCTAssertEqual(t.kind, .swap)
        XCTAssertEqual(t.venue, "Uniswap")
        XCTAssertEqual(t.amount, "10")
        XCTAssertEqual(t.sell, "USDC")
        XCTAssertEqual(t.buy, "ETH")
        XCTAssertEqual(t.chainName, "base")
    }

    func testUniswapTakesTheSwapAlreadyTyped() {
        let typed = "sure. swap 0.05 eth to usdc on arbitrum"
        XCTAssertEqual(SponsorMenu.action(for: .uniswap, typed: typed, privateAI: nil),
                       .trade(TradeIntent.parse(typed)!))
        // A Flash order typed is not Uniswap's: the starter swap instead.
        XCTAssertEqual(SponsorMenu.action(for: .uniswap, typed: "stop-loss eth at 2800", privateAI: nil),
                       .trade(TradeIntent.parse(SponsorMenu.swapStarter)!))
    }

    func testDefinitiveStartsATrailingStopWithNoPriceToGetWrong() throws {
        guard case .trade(let t) = SponsorMenu.action(for: .definitive, typed: "hello", privateAI: nil) else {
            return XCTFail("Definitive should open the trade panel")
        }
        XCTAssertEqual(t.kind, .trailingStop)
        XCTAssertEqual(t.venue, "Flash")
        XCTAssertEqual(t.sell, "ETH")
        XCTAssertEqual(t.trailPercent, "10")
        XCTAssertNil(t.price)
    }

    func testDefinitiveTakesAFlashOrderAlreadyTypedButNotASwap() {
        let typed = "stop-loss eth at 2800"
        XCTAssertEqual(SponsorMenu.action(for: .definitive, typed: typed, privateAI: nil),
                       .trade(TradeIntent.parse(typed)!))
        XCTAssertEqual(SponsorMenu.action(for: .definitive, typed: "swap 1 eth to usdc", privateAI: nil),
                       .trade(TradeIntent.parse(SponsorMenu.flashStarter)!))
    }

    func testZeroGShowsItsStateWhenOnAndOpensSettingsWhenOff() {
        XCTAssertEqual(SponsorMenu.action(for: .zeroG, typed: "", privateAI: true), .privateAIStatus)
        XCTAssertEqual(SponsorMenu.action(for: .zeroG, typed: "", privateAI: false), .openApp(path: "settings"))
        XCTAssertEqual(SponsorMenu.action(for: .zeroG, typed: "", privateAI: nil), .openApp(path: "settings"))
    }

    func testTheStatusLineNamesTheLastReceipt() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let at = (now.timeIntervalSince1970 - 180) * 1000
        XCTAssertEqual(SponsorMenu.statusLine(receipts: [["at": at, "teeVerified": true, "model": "0gm"]], now: now),
                       "Private AI on 0G is on · last 3 min ago · TEE verified")
        XCTAssertEqual(SponsorMenu.statusLine(receipts: [["at": at, "teeVerified": NSNull()]], now: now),
                       "Private AI on 0G is on · last 3 min ago")
        XCTAssertEqual(SponsorMenu.statusLine(receipts: [], now: now), "Private AI on 0G is on · no answers yet")
        // The server could not be reached: the switch's state is still known.
        XCTAssertEqual(SponsorMenu.statusLine(receipts: nil, now: now), "Private AI on 0G is on")
    }
}
