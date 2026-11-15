import Foundation
import StoreKit

/// Monthly support and one-time tips through the App Store (StoreKit 2). Unlocks nothing.
@MainActor @Observable
final class SupportStore {
    static let shared = SupportStore()

    private(set) var monthly: [Product] = []
    private(set) var oneTime: [Product] = []
    /// The monthly support that is running now (nil when none).
    private(set) var activeMonthly: Product?
    private(set) var loaded = false
    private(set) var failed = false
    private(set) var purchasing: String?
    /// Set after a purchase went through, for the thank-you note.
    var thanked = false

    private var updates: Task<Void, Never>?

    /// Called once at launch: finishes renewals and purchases made elsewhere (other device, Ask to Buy).
    func start() {
        guard updates == nil else { return }
        updates = Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refreshEntitlements()
            }
        }
    }

    func load() async {
        do {
            let products = try await Product.products(for: Support.allIDs)
            monthly = Support.sorted(products, id: \.id, kind: .monthly)
            oneTime = Support.sorted(products, id: \.id, kind: .oneTime)
            failed = products.isEmpty
        } catch {
            failed = true
        }
        loaded = true
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var active: Product?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil,
                  Support.parse(t.productID)?.kind == .monthly else { continue }
            active = monthly.first { $0.id == t.productID } ?? active
        }
        activeMonthly = active
    }

    func buy(_ product: Product) async {
        purchasing = product.id
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(.verified(let t)):
                await t.finish()
                thanked = true
                await refreshEntitlements()
            default: break // cancelled, pending (Ask to Buy) or unverified
            }
        } catch {
            failed = monthly.isEmpty && oneTime.isEmpty
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }
}
