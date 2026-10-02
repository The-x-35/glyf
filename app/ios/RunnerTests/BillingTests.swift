import StoreKit
import StoreKitTest
import XCTest

/// Billing against Glyf.storekit: the same four products and group as App
/// Store Connect, sold by StoreKit testing, so a purchase can be made here
/// without an Apple account. What comes back is what the server checks.
@MainActor
final class BillingTests: XCTestCase {
    private static let ids = ["com.arpit.glyf.plus.monthly", "com.arpit.glyf.plus.yearly",
                              "com.arpit.glyf.max.monthly", "com.arpit.glyf.max.yearly"]
    private static let probe = "com.arpit.glyf.storekit.probe"
    private var session: SKTestSession!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "Glyf")
        session.disableDialogs = true
        session.clearTransactions()
        // StoreKit testing must be in charge, not Apple's sandbox: since the
        // plans exist in App Store Connect (2026-10-02) the sandbox sells them
        // too, and a purchase there waits for a signed-in Apple Account. The
        // probe is a product only Glyf.storekit has. Command-line runs on this
        // Mac can't reach StoreKit testing (SKInternalErrorDomain 3); run
        // these from Xcode, where the scheme's Glyf.storekit is in charge.
        if try await Product.products(for: [Self.probe]).isEmpty {
            throw XCTSkip("StoreKit testing isn't in charge here: run BillingTests from Xcode")
        }
    }

    func testPricesComeFromTheStore() async throws {
        let items = try await Billing.shared.products(ids: Self.ids)
        XCTAssertEqual(items.count, 4)
        let plus = try XCTUnwrap(items.first { $0["id"] as? String == "com.arpit.glyf.plus.yearly" })
        XCTAssertEqual(plus["period"] as? String, "year")
        XCTAssertEqual(plus["name"] as? String, "Glyf Plus")
        // Whole amounts come without cents: "$20", not "$20.00".
        XCTAssertEqual(plus["price"] as? String, "$20")
    }

    func testAPurchaseComesBackSignedAndIsHeldAfterwards() async throws {
        let bought = await Billing.shared.purchase(id: "com.arpit.glyf.max.monthly")
        let jws = try XCTUnwrap(bought["jws"] as? String, "\(bought)")
        let payload = try Self.payload(jws)
        XCTAssertEqual(payload["productId"] as? String, "com.arpit.glyf.max.monthly")
        XCTAssertEqual(payload["environment"] as? String, "Xcode")
        XCTAssertNotNil(payload["originalTransactionId"])
        let held = await Billing.shared.entitlements()
        XCTAssertEqual(held.count, 1)
        XCTAssertEqual(try Self.payload(held[0])["productId"] as? String, "com.arpit.glyf.max.monthly")
    }

    func testAnUnknownProductIsAnAnswerNotACrash() async {
        let bought = await Billing.shared.purchase(id: "com.arpit.glyf.lifetime")
        XCTAssertNotNil(bought["error"] as? String)
    }

    private static func payload(_ jws: String) throws -> [String: Any] {
        let part = jws.split(separator: ".")[1]
        var b64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        let data = try XCTUnwrap(Data(base64Encoded: b64))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
