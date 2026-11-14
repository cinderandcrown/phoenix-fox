// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The App Store side of the plans: what is for sale, what this person holds, and buying.
//
// In a build that sells nothing, which is every build today and always the owner's, this
// never talks to the App Store and `allows` is always yes. The rules are in
// Core/StoreCatalog.swift and Core/Plan.swift, where they are unit-tested.
//
// The App Store signs every transaction and StoreKit checks the signature on the phone.
// That is enough to unlock something that runs on the phone. A hosted service that costs
// money for each use must check the subscription again on its own server.

import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    enum Outcome: Equatable {
        case bought
        /// The purchase waits for somebody else, such as a parent, to approve it.
        case waiting
        case cancelled
        case failed(String)
    }

    /// False in a build that sells nothing.
    let selling: Bool

    @Published private(set) var access: Access
    /// The subscriptions on sale, in the catalog's order, with the App Store's prices.
    @Published private(set) var products: [Product] = []
    /// Why the plans could not be shown, in words for the screen.
    @Published private(set) var problem: String?
    @Published private(set) var isLoading = false

    private let defaults: UserDefaults
    private var listener: Task<Void, Never>?
    private var checkedAt = Date.distantPast

    private static let planKey = "store.plan"
    private static let recheckAfter: TimeInterval = 60 * 60

    init(
        selling: Bool = StoreSwitch.isOn(
            flavor: .current,
            infoValue: Bundle.main.object(forInfoDictionaryKey: StoreSwitch.infoKey)
        ),
        defaults: UserDefaults = .standard
    ) {
        self.selling = selling
        self.defaults = defaults
        // The plan seen last time stands until the App Store answers, so a subscriber is
        // not refused in the first second after launch or with no signal.
        let remembered = defaults.string(forKey: Self.planKey).flatMap(Plan.init(rawValue:)) ?? .free
        access = selling ? Access(selling: true, plan: remembered) : .everything
    }

    /// Whether the plan covers a feature. Always yes in a build that sells nothing.
    func allows(_ feature: PaidFeature) -> Bool {
        if selling, Date().timeIntervalSince(checkedAt) > Self.recheckAfter {
            Task { await refresh() }
        }
        return access.allows(feature)
    }

    /// Starts listening for purchases, renewals, and refunds made outside this screen, and
    /// reads what is held. Does nothing in a build that sells nothing.
    func start() {
        guard selling, listener == nil else { return }
        listener = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.take(update)
            }
        }
        Task { await refresh() }
    }

    /// Reads what this person holds from the App Store's signed records on the phone.
    func refresh() async {
        guard selling else { return }
        checkedAt = Date()
        var held: [String] = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded else { continue }
            held.append(transaction.productID)
        }
        let plan = StoreCatalog.plan(owning: held)
        defaults.set(plan.rawValue, forKey: Self.planKey)
        if access.plan != plan {
            access = Access(selling: true, plan: plan)
        }
    }

    /// Fetches the subscriptions on sale, with prices in the person's own currency.
    func loadProducts() async {
        guard selling, products.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let wanted = StoreCatalog.products().map(\.id)
        do {
            let found = try await Product.products(for: wanted)
            products = wanted.compactMap { id in found.first { $0.id == id } }
            problem = products.isEmpty ? "The App Store has no plans to show yet." : nil
        } catch {
            problem = "The plans could not be loaded. Check the connection and try again."
        }
    }

    /// Records the result of a purchase that the Plan screen started.
    func record(_ result: Product.PurchaseResult) async -> Outcome {
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                return .failed("The App Store's receipt could not be checked, so nothing was unlocked. You have not lost the purchase. Try Restore purchases.")
            }
            await transaction.finish()
            await refresh()
            return .bought
        case .pending:
            return .waiting
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Asks the App Store again for everything bought with this Apple Account.
    func restore() async -> Outcome {
        guard selling else { return .cancelled }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed("The App Store could not be reached. Try again in a moment.")
        }
        await refresh()
        return access.plan == .free ? .failed("This Apple Account holds no Phoenix Fox plan.") : .bought
    }

    private func take(_ update: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = update {
            await transaction.finish()
        }
        await refresh()
    }
}
