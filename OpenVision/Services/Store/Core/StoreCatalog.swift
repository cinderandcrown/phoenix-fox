// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The subscriptions as App Store Connect must name them, and the switch that decides
// whether this build sells anything at all.
//
// The switch is the build setting PHOENIX_FOX_STORE, which reaches the app through
// Info.plist. It is NO in the project. The owner's build never sells, whatever the setting
// says. A build that does not sell unlocks everything and never talks to the App Store.

import Foundation

enum BillingPeriod: String, CaseIterable, Sendable {
    case monthly
    case yearly

    /// Follows a price: "$2.99 a month".
    var each: String {
        switch self {
        case .monthly: return "a month"
        case .yearly: return "a year"
        }
    }
}

/// One subscription: a plan for a month or for a year.
struct PlanProduct: Hashable, Sendable {
    let plan: Plan
    let period: BillingPeriod

    /// The product identifier in App Store Connect. Once a product exists there the
    /// identifier can never be changed or used again, so neither can these.
    var id: String { StoreCatalog.prefix + plan.rawValue + "." + period.rawValue }
}

enum StoreCatalog {
    static let prefix = "com.cinderandcrown.phoenixfox.plan."

    /// The one subscription group every plan belongs to, so that a person holds one plan at
    /// a time and moves up or down between them.
    static let groupName = "Phoenix Fox plans"

    /// Whether Cinder & Crown runs a metered model service for subscribers. It does not yet,
    /// so Included AI is not offered.
    static let hostedAIReady = false

    /// Terms of Use. Hosted URL pending Nicholas (REVIEW_CHECKLIST P1); must not be nil for sale.
    /// Until GitHub Pages / legal.cinderandcrown.com is live, this points at the in-repo draft
    /// rendered via raw GitHub (About screen also shows an in-app copy).
    static let termsURL = URL(string: "https://cinderandcrown.github.io/phoenix-fox/legal/terms")!

    /// Privacy Policy. Same hosting note as `termsURL` — never nil for App Store sale gates.
    static let privacyURL = URL(string: "https://cinderandcrown.github.io/phoenix-fox/legal/privacy")!

    /// The paid plans a person can buy today, cheapest first.
    static func plansOnSale(hostedAI: Bool = hostedAIReady) -> [Plan] {
        hostedAI ? [.ownAI, .includedAI, .botTeam] : [.ownAI, .botTeam]
    }

    static func products(hostedAI: Bool = hostedAIReady) -> [PlanProduct] {
        plansOnSale(hostedAI: hostedAI).flatMap { plan in
            BillingPeriod.allCases.map { PlanProduct(plan: plan, period: $0) }
        }
    }

    /// The subscription with this identifier, whether or not it is still on sale. Somebody
    /// who bought a plan keeps it after it leaves the shelf.
    static func product(id: String) -> PlanProduct? {
        guard id.hasPrefix(prefix) else { return nil }
        let parts = id.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let plan = Plan(rawValue: String(parts[0])), plan != .free,
              let period = BillingPeriod(rawValue: String(parts[1])) else { return nil }
        return PlanProduct(plan: plan, period: period)
    }

    /// The best plan among the subscriptions a person holds.
    static func plan(owning ids: [String]) -> Plan {
        ids.compactMap { product(id: $0)?.plan }.max() ?? .free
    }

    /// What Apple requires on the screen that sells a subscription and this app does not have yet.
    static func missingBeforeSale(terms: URL? = termsURL, privacy: URL? = privacyURL) -> [String] {
        var missing: [String] = []
        // Hosted URLs are non-nil constants; keep the gate for overrides / tests.
        if terms == nil { missing.append("the terms of use") }
        if privacy == nil { missing.append("the privacy policy") }
        return missing
    }
}

enum StoreSwitch {
    static let infoKey = "PhoenixFoxStoreEnabled"

    /// Whether the running app sells plans. Never in the owner's build, and never before the
    /// selling screen can show everything Apple requires on it.
    static func isOn(
        flavor: BuildFlavor,
        infoValue: Any?,
        missing: [String] = StoreCatalog.missingBeforeSale()
    ) -> Bool {
        flavor != .owner && InfoFlag.isOn(infoValue) && missing.isEmpty
    }
}

/// What the running app may do.
struct Access: Equatable, Sendable {
    /// False in a build that sells nothing, where everything is unlocked.
    let selling: Bool
    let plan: Plan

    static let everything = Access(selling: false, plan: .free)

    func allows(_ feature: PaidFeature) -> Bool {
        !selling || plan >= feature.plan
    }
}
