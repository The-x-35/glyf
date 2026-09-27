import Foundation
import StoreKit

/// Plus and Max through the App Store, with StoreKit 2.
///
/// The phone never decides a plan. It shows the store's own prices, runs
/// Apple's purchase sheet, and hands over the signed transactions it holds;
/// the server checks Apple's signature on each one before the account's plan
/// changes (server/src/lib/appstore.ts).
@MainActor
final class Billing {
    static let shared = Billing()
    private init() {}

    private var products: [String: Product] = [:]
    private var listener: Task<Void, Never>?

    /// Renewals, refunds and purchases approved elsewhere (Ask to Buy) arrive
    /// while the app runs; each is handed on as Apple's signed transaction.
    func start(onUpdate: @escaping (String) -> Void) {
        guard listener == nil else { return }
        listener = Task {
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                onUpdate(update.jwsRepresentation)
            }
        }
    }

    /// The store's names and prices, in the person's own currency.
    func products(ids: [String]) async throws -> [[String: Any]] {
        let found = try await Product.products(for: ids)
        for product in found { products[product.id] = product }
        return found.map { product in
            var item: [String: Any] = [
                "id": product.id, "price": product.displayPrice, "name": product.displayName,
            ]
            if let period = product.subscription?.subscriptionPeriod {
                item["period"] = switch period.unit {
                case .year: "year"
                case .month: "month"
                case .week: "week"
                default: "day"
                }
            }
            return item
        }
    }

    /// Apple's purchase sheet. A purchase comes back as its signed
    /// transaction for the server; cancelling and Ask to Buy's "pending" are
    /// answers, not failures.
    func purchase(id: String, accountToken: UUID? = nil) async -> [String: Any] {
        do {
            var product = products[id]
            if product == nil { product = try await Product.products(for: [id]).first }
            guard let product else {
                return ["error": "That plan isn't available in the App Store right now."]
            }
            var options: Set<Product.PurchaseOption> = []
            if let accountToken { options.insert(.appAccountToken(accountToken)) }
            switch try await product.purchase(options: options) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return ["error": "The App Store couldn't confirm that purchase."]
                }
                await transaction.finish()
                return ["jws": verification.jwsRepresentation]
            case .userCancelled:
                return ["cancelled": true]
            case .pending:
                return ["pending": true]
            @unknown default:
                return ["error": "The App Store gave an answer Glyf doesn't know."]
            }
        } catch {
            return ["error": error.localizedDescription]
        }
    }

    /// Every Glyf subscription this Apple ID holds right now, signed.
    func entitlements() async -> [String] {
        var held: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified = result { held.append(result.jwsRepresentation) }
        }
        return held
    }

    /// Restore Purchases: asks the App Store to bring this Apple ID's
    /// purchases back to this phone, then hands over what it holds.
    func restore() async -> [String: Any] {
        do {
            try await AppStore.sync()
        } catch {
            return ["error": error.localizedDescription, "transactions": await entitlements()]
        }
        return ["transactions": await entitlements()]
    }
}
