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
    private var session: SKTestSession!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "Glyf")
        session.disableDialogs = true
        session.clearTransactions()
        // Command-line runs on this Mac can't reach StoreKit testing's local
        // store (SKInternalErrorDomain 3); run these from Xcode, where the
        // scheme's Glyf.storekit is in charge.
        if try await Product.products(for: Self.ids).isEmpty {
            throw XCTSkip("StoreKit testing isn't reachable here: run BillingTests from Xcode")
        }
    }

    func testPricesComeFromTheStore() async throws {
        let items = try await Billing.shared.products(ids: Self.ids)
        XCTAssertEqual(items.count, 4)
        let plus = try XCTUnwrap(items.first { $0["id"] as? String == "com.arpit.glyf.plus.yearly" })
        XCTAssertEqual(plus["period"] as? String, "year")
        XCTAssertEqual(plus["name"] as? String, "Glyf Plus")
        XCTAssertTrue((plus["price"] as? String ?? "").contains("19.99"))
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
