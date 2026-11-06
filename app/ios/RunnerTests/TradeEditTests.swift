import XCTest
@testable import Runner

/// The trade panel's edits (TradeEdit): what a typed value, a picked token
/// or a picked chain does to the trade, the picker's filtering, and the
/// cross-chain swaps read from words.
final class TradeEditTests: XCTestCase {

    private func read(_ text: String) -> TradeIntent { TradeIntent.parse(text)! }

    // MARK: typed values

    func testTheAmountOfASwapIsWhatsSpent() {
        let i = TradeEdit.apply(.amount, "25.5", to: read("swap 10 usdc to eth on base"))
        XCTAssertEqual(i.amount, "25.5")
        XCTAssertEqual(i.query["amount"], "25.5")
        XCTAssertEqual(TradeEdit.label(.amount, i), "Amount in USDC")
    }

    func testAnEmptyAmountOnASellIsEverythingHeld() {
        let i = TradeEdit.apply(.amount, "", to: read("swap 10 usdc to eth on base"))
        XCTAssertNil(i.amount)
        XCTAssertEqual(TradeEdit.shown(.amount, i), "All")
        XCTAssertNil(i.query["amount"])
    }

    func testBuyingAnAmountEditsWhatComesBack() {
        let i = TradeEdit.apply(.amount, "0.2", to: read("buy 0.1 eth with usdc"))
        XCTAssertEqual(i.buyAmount, "0.2")
        XCTAssertNil(i.amount)
        XCTAssertEqual(TradeEdit.label(.amount, i), "ETH to get")
    }

    func testABuyOrderIsTypedInDollars() {
        let i = read("buy $20 of eth at 2800")
        XCTAssertEqual(TradeEdit.amountUnit(i), .dollars)
        let j = TradeEdit.apply(.amount, "75", to: i)
        XCTAssertEqual(j.amount, "75")
        XCTAssertEqual(TradeEdit.shown(.amount, j), "$75")
    }

    func testAPriceEditReplacesAStartersDistance() {
        var i = SponsorMenu.starter(.limit, chain: "base")!
        XCTAssertTrue(i.awaitingPrice)
        i = TradeEdit.apply(.price, "2,500", to: i)
        XCTAssertEqual(i.price, "2.500", "a comma is a decimal point while typing")
        i = TradeEdit.apply(.price, "2500", to: i)
        XCTAssertEqual(i.price, "2500")
        XCTAssertNil(i.pricePercent)
        XCTAssertFalse(i.awaitingPrice)
        XCTAssertEqual(i.query["price"], "2500")
    }

    func testBracketPricesAreEditedApartAndCheckedTogether() {
        var i = read("my eth tp 4500 sl 3000")
        XCTAssertEqual(TradeEdit.fields(i), [.amount, .price, .stopPrice])
        XCTAssertNil(TradeEdit.problem(i))
        i = TradeEdit.apply(.stopPrice, "4600", to: i)
        XCTAssertEqual(i.stopPrice, "4600")
        XCTAssertEqual(TradeEdit.problem(i), "Take profit must be above the stop-loss")
        i = TradeEdit.apply(.price, "5000", to: i)
        XCTAssertNil(TradeEdit.problem(i))
        XCTAssertEqual(i.query["stopPrice"], "4600")
    }

    func testTrailAndDuration() {
        var t = read("trail my eth by 5%")
        t = TradeEdit.apply(.trail, "7.5", to: t)
        XCTAssertEqual(t.trailPercent, "7.5")
        XCTAssertEqual(TradeEdit.shown(.trail, t), "7.5%")
        XCTAssertEqual(TradeEdit.problem(TradeEdit.apply(.trail, "80", to: t)), "Trail between 0.5% and 50%")

        var w = read("buy $100 of eth over a day")
        XCTAssertEqual(TradeEdit.value(.duration, w), "1")
        w = TradeEdit.apply(.duration, "0.5", to: w)
        XCTAssertEqual(w.durationSeconds, 43_200)
        XCTAssertEqual(TradeEdit.shown(.duration, w), "12 hours")
        w = TradeEdit.apply(.duration, "7", to: w)
        XCTAssertEqual(TradeEdit.shown(.duration, w), "1 week")
        XCTAssertEqual(w.query["duration"], "604800")
    }

    func testCleanNumbers() {
        XCTAssertEqual(TradeEdit.cleanNumber("1.2.3"), "1.23")
        XCTAssertEqual(TradeEdit.cleanNumber(".5"), "0.5")
        XCTAssertEqual(TradeEdit.cleanNumber("007"), "7")
        XCTAssertEqual(TradeEdit.cleanNumber("12a"), "12")
    }

    // MARK: tokens and chains

    func testPickingASwapTokenSetsItsAddress() {
        let pepe = TokenPick(symbol: "PEPE", name: "Pepe", address: "0xB4fDe59a779991bfB6a52253B51947828b982be3")
        let i = TradeEdit.pick(pepe, side: .buy, in: read("swap 10 usdc to eth on base"))
        XCTAssertEqual(i.buy, "PEPE")
        XCTAssertEqual(i.query["buyAddress"], "0xB4fDe59a779991bfB6a52253B51947828b982be3")
        XCTAssertNil(i.sellAddress)
    }

    func testPickingTheOtherSidesTokenFlips() {
        let i = TradeEdit.pick(TokenPick(symbol: "ETH", name: "Ether", native: true), side: .sell,
                               in: read("swap 10 usdc to eth on base"))
        XCTAssertEqual(i.sell, "ETH")
        XCTAssertEqual(i.buy, "USDC")
        XCTAssertEqual(i.amount, "10")
    }

    func testFlipMovesTheChainsOfACrossChainSwap() {
        let i = TradeEdit.flip(read("swap 50 usdc on base to eth on arbitrum"))
        XCTAssertEqual(i.sell, "ETH")
        XCTAssertEqual(i.buy, "USDC")
        XCTAssertEqual(i.chainName, "arbitrum")
        XCTAssertEqual(i.buyChain, "base")
    }

    func testAFlashOrderPickChangesItsAssetNotTheDollarSide() {
        let link = TokenPick(symbol: "LINK", name: "Chainlink")
        let buy = TradeEdit.pick(link, side: .sell, in: read("buy $20 of eth at 2800"))
        XCTAssertEqual(buy.buy, "LINK")
        XCTAssertEqual(buy.sell, "USDC")
        let sell = TradeEdit.pick(link, side: .buy, in: read("stop loss my eth at 3000"))
        XCTAssertEqual(sell.sell, "LINK")
        XCTAssertEqual(sell.buy, "USDC")
        let bridge = TradeEdit.pick(TokenPick(symbol: "USDC", name: "USD Coin"), side: .sell,
                                    in: read("move 50 usdc from base to arbitrum"))
        XCTAssertEqual(bridge.sell, "USDC")
        XCTAssertEqual(bridge.buy, "USDC")
    }

    func testChainsPerKind() {
        XCTAssertEqual(TradeEdit.chains(for: read("swap 10 usdc to eth")), ["base", "ethereum", "arbitrum", "optimism", "unichain"])
        XCTAssertTrue(TradeEdit.chains(for: read("stop loss my eth at 3000")).contains("solana"))
        XCTAssertFalse(TradeEdit.chains(for: read("swap 10 usdc to eth")).contains("solana"))
    }

    func testAFlashOrderMovedToSolanaTradesSol() {
        let i = TradeEdit.pickChain("solana", side: .sell, in: read("stop loss my eth at 3000"))
        XCTAssertEqual(i.chainName, "solana")
        XCTAssertEqual(i.sell, "SOL")
        XCTAssertEqual(i.buy, "USDC")
        let back = TradeEdit.pickChain("base", side: .sell, in: i)
        XCTAssertEqual(back.sell, "ETH")
    }

    func testYouGetOnAnotherChainIsCrossChain() {
        let i = TradeEdit.pickChain("arbitrum", side: .buy, in: read("swap 10 usdc to eth on base"))
        XCTAssertEqual(i.buyChain, "arbitrum")
        XCTAssertEqual(i.query["buyChain"], "arbitrum")
        XCTAssertEqual(i.detail, "Base → Arbitrum · Uniswap")
        // Back on the same chain: an ordinary swap.
        XCTAssertNil(TradeEdit.pickChain("base", side: .buy, in: i).buyChain)
        // A bridge's buy side is where it lands.
        let move = TradeEdit.pickChain("optimism", side: .buy, in: read("move 50 usdc from base to arbitrum"))
        XCTAssertEqual(move.toChain, "optimism")
    }

    func testSameTokenOnBothSidesIsAProblemOnlyOnOneChain() {
        var i = read("swap 10 usdc to eth on base")
        i.buy = "USDC"
        XCTAssertEqual(TradeEdit.problem(i), "Pick two different tokens")
        i.buyChain = "arbitrum"
        XCTAssertNil(TradeEdit.problem(i))
    }

    // MARK: picker rows

    func testFilterRanksSymbolThenPrefixThenName() {
        let rows = [TokenPick(symbol: "XPEPE", name: "x"), TokenPick(symbol: "PEPE", name: "Pepe"),
                    TokenPick(symbol: "PEPECOIN", name: "p"), TokenPick(symbol: "FROG", name: "Pepe's friend")]
        XCTAssertEqual(TradeEdit.filter(rows, query: "pepe").map(\.symbol), ["PEPE", "PEPECOIN", "FROG", "XPEPE"])
        XCTAssertEqual(TradeEdit.filter(rows, query: "$PEPE").first?.symbol, "PEPE")
        XCTAssertEqual(TradeEdit.filter(rows, query: "").count, 4)
        XCTAssertTrue(TradeEdit.filter(rows, query: "zzz").isEmpty)
        let addressed = [TokenPick(symbol: "PEPE", name: "Pepe", address: "0xAbC0000000000000000000000000000000000001")]
        XCTAssertEqual(TradeEdit.filter(addressed, query: "0xabc0000000000000000000000000000000000001").count, 1)
    }

    func testBuiltInRowsPerChainAndMergeKeepsThemFirst() {
        XCTAssertEqual(TradeEdit.builtIn(chain: "solana").map(\.symbol), ["SOL", "USDC", "USDT"])
        XCTAssertEqual(TradeEdit.builtIn(chain: "base").map(\.symbol), ["ETH", "USDC", "WETH", "DAI", "cbBTC"])
        let server = [TokenPick(symbol: "USDC", name: "USD Coin", address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", logo: "https://x/usdc.png"),
                      TokenPick(symbol: "PEPE", name: "Pepe", address: "0xB4fDe59a779991bfB6a52253B51947828b982be3")]
        let merged = TradeEdit.merge(TradeEdit.builtIn(chain: "base"), server)
        XCTAssertEqual(merged.first?.symbol, "ETH")
        XCTAssertEqual(merged.filter { $0.symbol == "USDC" }.count, 1)
        XCTAssertEqual(merged.first { $0.symbol == "USDC" }?.logo, "https://x/usdc.png")
        XCTAssertEqual(merged.last?.symbol, "PEPE")
    }

    func testTokenRowsReadTheServersJSON() {
        let t = TokenPick(json: ["symbol": "ETH", "name": "Ether", "address": "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
                                 "decimals": 18, "native": true, "logoURI": "https://x/eth.png"])
        XCTAssertEqual(t?.native, true)
        XCTAssertEqual(t?.logo, "https://x/eth.png")
        XCTAssertNil(TokenPick(json: ["name": "no symbol"]))
    }

    // MARK: words

    func testACrossChainSwapReadsBothChains() {
        let i = read("swap 50 usdc on base to eth on arbitrum")
        XCTAssertEqual(i.kind, .swap)
        XCTAssertEqual(i.amount, "50")
        XCTAssertEqual(i.sell, "USDC")
        XCTAssertEqual(i.buy, "ETH")
        XCTAssertEqual(i.chainName, "base")
        XCTAssertEqual(i.buyChain, "arbitrum")
        XCTAssertEqual(i.title, "Swap 50 USDC → ETH on Arbitrum")
        XCTAssertEqual(i.query["buyChain"], "arbitrum")
        // The same token moved is a swap across chains too.
        XCTAssertEqual(read("swap 20 usdc on base to usdc on optimism").buyChain, "optimism")
        XCTAssertNil(TradeIntent.parse("swap 20 usdc on base to usdc on base"))
    }

    func testAMemeCoinSwapLandsInTheSamePanel() {
        let i = read("swap 0.1 eth to pepe on base")
        XCTAssertEqual(i.kind, .swap)
        XCTAssertEqual(i.buy, "PEPE")
        XCTAssertEqual(i.chainName, "base")
        XCTAssertNil(i.buyChain)
    }
}
