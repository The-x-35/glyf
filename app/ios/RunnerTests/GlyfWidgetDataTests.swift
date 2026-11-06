import XCTest
@testable import Runner

/// The trade Live Activity's mapping from the trade screen's steps, the
/// widgets' data (prices, the next event, quick glyfs) and the intents'
/// answers: the pure halves of docs/WIDGETS-AND-ISLAND.md.
final class GlyfWidgetDataTests: XCTestCase {

    // MARK: Trade activity

    func testAStopLossOnSolanaReadsAsItsPairAmountAndTrigger() {
        let a = GlyfTradeActivity.attributes(id: "t1", query: [
            "kind": "stop-loss", "sell": "sol", "buy": "usdc", "amount": "2", "price": "172", "chain": "solana",
        ])
        XCTAssertEqual(a.pair, "SOL → USDC")
        XCTAssertEqual(a.amount, "2 SOL")
        XCTAssertEqual(a.trigger, "at $172")
        XCTAssertEqual(a.chain, "Solana")
        XCTAssertFalse(a.cancellable, "Solana's Flash orders have no cancel in Glyf yet")
    }

    func testFlashOnBaseIsCancellableAndDollarAmountsReadAsDollars() {
        let a = GlyfTradeActivity.attributes(id: "t2", query: [
            "kind": "trailing-stop", "sell": "ETH", "buy": "USDC", "amount": "50", "usd": "1", "trail": "5", "chain": "base",
        ])
        XCTAssertTrue(a.cancellable)
        XCTAssertEqual(a.amount, "$50")
        XCTAssertEqual(a.trigger, "trail 5%")
        XCTAssertEqual(a.chain, "Base")
        let swap = GlyfTradeActivity.attributes(id: "t3", query: ["kind": "swap", "sell": "ETH", "buy": "USDC"])
        XCTAssertFalse(swap.cancellable)
        XCTAssertNil(swap.trigger)
        let twap = GlyfTradeActivity.attributes(id: "t4", query: ["kind": "twap", "sell": "USDC", "buy": "ETH", "duration": "604800"])
        XCTAssertEqual(twap.trigger, "over 7d")
    }

    func testEveryTradeStateLandsOnItsPhase() {
        func phase(_ kind: String, _ state: String, _ title: String, reopen: Bool = false) -> GlyfTradeAttributes.Phase {
            GlyfTradeActivity.content(kind: kind, state: state, title: title, detail: nil, wallet: nil,
                                      link: nil, orderId: nil, reopen: reopen).phase
        }
        XCTAssertEqual(phase("stop-loss", "working", "Asking Flash…"), .placing)
        XCTAssertEqual(phase("stop-loss", "working", "Sign the stop-loss in Phantom"), .waiting)
        XCTAssertEqual(phase("swap", "working", "Swap ETH for USDC: confirm in MetaMask", reopen: true), .waiting)
        XCTAssertEqual(phase("stop-loss", "working", "Approve the setup in Phantom"), .waiting)
        XCTAssertEqual(phase("stop-loss", "working", "Placing the order…"), .placing)
        XCTAssertEqual(phase("stop-loss", "done", "Stop-loss set"), .placed)
        XCTAssertEqual(phase("swap", "done", "Swapped"), .confirmed)
        XCTAssertEqual(phase("send", "done", "Sent"), .confirmed)
        XCTAssertEqual(phase("swap", "submitted", "Swap sent"), .submitted)
        XCTAssertEqual(phase("swap", "failed", "The swap reverted"), .failed)
    }

    func testTheWalletIsNamedAndOnlyHttpsLinksAreKept() {
        let waiting = GlyfTradeActivity.content(kind: "limit", state: "working", title: "Sign the limit in Phantom",
                                                detail: nil, wallet: "Phantom", link: "javascript:alert(1)",
                                                orderId: nil, reopen: false)
        XCTAssertEqual(GlyfTradeActivity.status(waiting), "Phantom")
        XCTAssertEqual(GlyfTradeActivity.headline(waiting, chain: "Solana"), "Waiting for Phantom")
        XCTAssertNil(waiting.link)
        let placed = GlyfTradeActivity.content(kind: "limit", state: "done", title: "Limit order placed", detail: nil,
                                               wallet: nil, link: "https://app.definitive.fi/orders/abc",
                                               orderId: "abc", reopen: false)
        XCTAssertEqual(GlyfTradeActivity.status(placed), "Placed")
        XCTAssertEqual(GlyfTradeActivity.linkLabel(placed.link), "Definitive")
        XCTAssertNil(GlyfTradeActivity.dismissal(.placed), "a placed order keeps its Cancel")
        XCTAssertNotNil(GlyfTradeActivity.dismissal(.confirmed))
        XCTAssertEqual(GlyfTradeActivity.cancelURL(orderId: "abc")?.absoluteString, "glyf://open?path=flash-cancel&id=abc")
    }

    func testTheWalletIsReadFromTheStep() {
        XCTAssertEqual(GlyfTradeActivity.wallet(in: "Swap ETH for USDC: confirm in MetaMask", chain: "Base"), "MetaMask")
        XCTAssertEqual(GlyfTradeActivity.wallet(in: "Placing the order…", chain: "Solana"), "Phantom")
        XCTAssertNil(GlyfTradeActivity.wallet(in: "Asking Uniswap…", chain: "Base"))
    }

    func testTheActivityStaysUnderActivityKitsFourKilobytes() throws {
        let a = GlyfTradeActivity.attributes(id: String(repeating: "x", count: 40), query: [
            "kind": "bracket", "sell": "ETH", "buy": "USDC", "amount": "1.25", "price": "4200", "stopPrice": "3500",
        ])
        let s = GlyfTradeActivity.content(kind: a.kind, state: "done", title: "Bracket set",
                                          detail: String(repeating: "d", count: 300), wallet: "MetaMask",
                                          link: "https://app.definitive.fi/orders/" + String(repeating: "a", count: 64),
                                          orderId: String(repeating: "a", count: 64), reopen: false)
        XCTAssertEqual(a.trigger, "$4200 / $3500")
        let bytes = try JSONEncoder().encode(a).count + JSONEncoder().encode(s).count
        XCTAssertLessThan(bytes, 4096)
    }

    // MARK: Widgets

    func testPricesAndChangesReadTheWayMoneyIsWritten() {
        XCTAssertEqual(GlyfWidgetData.price(104_212.4), "$104,212")
        XCTAssertEqual(GlyfWidgetData.price(187.051), "$187.05")
        XCTAssertEqual(GlyfWidgetData.price(0.02134), "$0.0213")
        XCTAssertEqual(GlyfWidgetData.change(1.84), "+1.8%")
        XCTAssertEqual(GlyfWidgetData.change(-0.66), "−0.7%")
        XCTAssertEqual(GlyfWidgetData.change(0.01), "0.0%")
        XCTAssertEqual(GlyfWidgetData.change(nil), "–")
    }

    func testTheWatchlistIsTheSettingsOrTheDefault() {
        XCTAssertEqual(GlyfWidgetData.watchlist(settings: nil), ["BTC", "ETH", "SOL", "AAPL"])
        XCTAssertEqual(GlyfWidgetData.watchlist(settings: ["watchlist": ["$sol", " nvda", ""]]), ["SOL", "NVDA"])
    }

    func testPricesSurviveTheirFile() throws {
        let p = GlyfWidgetData.Prices(at: Date(timeIntervalSince1970: 1_800_000_000), tickers: GlyfWidgetData.sample)
        let back = try GlyfWidgetData.decoder.decode(GlyfWidgetData.Prices.self, from: GlyfWidgetData.encoder.encode(p))
        XCTAssertEqual(back, p)
    }

    func testTheNextEventIsTheOneOnNowOrNextWithItsCall() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let iso = ISO8601DateFormatter()
        func at(_ m: Double) -> String { iso.string(from: now.addingTimeInterval(m * 60)) }
        let rows: [[String: Any]] = [
            ["title": "Finished", "start": at(-90), "end": at(-30), "allDay": false],
            ["title": "Holiday", "start": at(-600), "end": at(900), "allDay": true],
            ["title": "Later", "start": at(120), "end": at(150), "allDay": false],
            ["title": "Standup", "start": at(10), "end": at(25), "allDay": false,
             "location": "https://meet.google.com/abc-defg-hij"],
            ["title": "Lunch", "start": at(10), "end": at(70), "allDay": false, "location": "Cafe Mondegar"],
        ]
        let next = GlyfWidgetData.nextEvent(GlyfWidgetData.events(fromRows: rows), now: now)
        XCTAssertEqual(next?.title, "Standup", "same start: the one with a call first")
        XCTAssertEqual(next?.join?.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertNil(next?.location)
        XCTAssertEqual(GlyfWidgetData.when(next!, now: now), "in 10 min")
        XCTAssertNil(GlyfWidgetData.nextEvent([], now: now))
    }

    func testOnlyCallLinksCountAsJoin() {
        XCTAssertEqual(GlyfWidgetData.joinURL(in: "Zoom https://us06web.zoom.us/j/853?pwd=x")?.host, "us06web.zoom.us")
        XCTAssertNil(GlyfWidgetData.joinURL(in: "https://example.com/agenda"))
        XCTAssertNil(GlyfWidgetData.joinURL(in: "http://meet.google.com/abc"), "never a plain-http link")
        XCTAssertNil(GlyfWidgetData.joinURL(in: nil))
    }

    func testQuickGlyfsAndSavedGlyfs() {
        let quick = GlyfWidgetData.quickGlyfs(settings: nil)
        XCTAssertEqual(quick.map(\.id), ["meet", "voice", "wallet", "vault"])
        XCTAssertEqual(quick.filter { $0.action == .link }.compactMap(\.url?.scheme), ["glyf", "glyf"])
        let saved = GlyfWidgetData.savedGlyfs(settings: ["customTitles": ["user.b": "standup", "user.a": "Meet link", "user.c": ""]])
        XCTAssertEqual(saved.map(\.title), ["Meet link", "standup"])
        XCTAssertEqual(GlyfWidgetData.shortLink("https://meet.google.com/abc-defg-hij"), "meet.google.com/abc-defg-hij")
    }

    // MARK: Intents

    func testRunGlyfListsSavedGlyfsBeforeTheBuiltIns() {
        let all = GlyfEntity.all(settings: ["customTitles": ["user.x": "Send my Meet link"]])
        XCTAssertEqual(all.first?.id, "user.x")
        XCTAssertTrue(all.contains { $0.id == "rewrite.polite" })
    }

    func testARewriteAnswersWithTheStyleAsked() throws {
        let json: [String: Any] = ["ok": true, "text": "Basic one", "options": [
            ["id": "basic", "label": "Basic", "text": "Basic one"],
            ["id": "work", "label": "Professional", "text": "Work one"],
        ]]
        XCTAssertEqual(try GlyfIntentParsing.pickRewrite(json, style: "work"), "Work one")
        XCTAssertEqual(try GlyfIntentParsing.pickRewrite(json, style: "emoji"), "Basic one")
        XCTAssertThrowsError(try GlyfIntentParsing.pickRewrite(["ok": false, "error": "No runs left"], style: "basic"))
    }

    func testAGlyfRunsStreamReadsAsItsText() throws {
        let body = "event: token\ndata: {\"t\":\"Hi \"}\n\nevent: token\ndata: {\"t\":\"there\"}\n\nevent: done\ndata: {\"text\":\"Hi there!\",\"remaining\":3}\n\n"
        XCTAssertEqual(try GlyfIntentParsing.streamText(body), "Hi there!")
        XCTAssertEqual(try GlyfIntentParsing.streamText("event: token\ndata: {\"t\":\"only tokens\"}\n\n"), "only tokens")
        XCTAssertThrowsError(try GlyfIntentParsing.streamText("event: error\ndata: {\"message\":\"Unknown glyf\"}\n\n"))
    }

    // MARK: Next meeting

    func testTheMeetingActivityStartsTenMinutesBeforeACallAndNotForOthers() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let call = URL(string: "https://meet.google.com/abc-defg-hij")!
        let soon = GlyfWidgetData.Event(title: "Standup", start: now.addingTimeInterval(3600),
                                        end: now.addingTimeInterval(5400), location: nil, join: call)
        XCTAssertEqual(GlyfMeetingAttributes.start(for: soon, now: now), now.addingTimeInterval(50 * 60))
        var close = soon
        close.start = now.addingTimeInterval(120)
        XCTAssertEqual(GlyfMeetingAttributes.start(for: close, now: now), now, "inside ten minutes: at once")
        var noCall = soon
        noCall.join = nil
        XCTAssertNil(GlyfMeetingAttributes.start(for: noCall, now: now))
        var far = soon
        far.start = now.addingTimeInterval(12 * 3600)
        far.end = now.addingTimeInterval(13 * 3600)
        XCTAssertNil(GlyfMeetingAttributes.start(for: far, now: now), "past iOS's eight hours")
        XCTAssertEqual(GlyfMeetingAttributes.service(URL(string: "https://us06web.zoom.us/j/1")!), "Zoom")
        XCTAssertNotEqual(GlyfMeetingAttributes.key(for: soon), GlyfMeetingAttributes.key(for: close))
    }
}
