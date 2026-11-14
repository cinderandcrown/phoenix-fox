// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The Plan screen: what each plan holds, which one this person has, and buying one.
//
// In a build that sells nothing it says so and lists the plans for reading only. That is
// every build today, and always the owner's. See docs/BUSINESS_MODEL.md.

import StoreKit
import SwiftUI

struct PlanView: View {
    @ObservedObject private var store = SubscriptionStore.shared
    @Environment(\.purchase) private var purchase

    @State private var buying: String?
    @State private var restoring = false
    @State private var managing = false
    @State private var notice: String?

    var body: some View {
        Form {
            if store.selling {
                yours
            } else {
                unlocked
            }
            planSection(.free)
            ForEach(shelf, id: \.self) { plan in
                planSection(plan)
            }
            if store.selling {
                account
            }
        }
        .navigationTitle("Plan")
        .task {
            await store.loadProducts()
            await store.refresh()
        }
        .manageSubscriptionsSheet(isPresented: $managing)
        .onChange(of: notice) { _, line in
            if let line { AccessibilityNotification.Announcement(line).post() }
        }
    }

    /// The paid plans to show. A build that sells nothing lists all of them, to be read.
    private var shelf: [Plan] {
        store.selling ? StoreCatalog.plansOnSale() : StoreCatalog.plansOnSale(hostedAI: true)
    }

    // MARK: - Sections

    private var unlocked: some View {
        Section {
            Label("Everything is unlocked", systemImage: "lock.open")
        } footer: {
            if BuildFlavor.current == .owner {
                Text("This is the owner's build. Every feature works, nothing is for sale in it, and it never asks the App Store for anything. The plans below are how a public build would be sold.")
            } else {
                Text("This build sells nothing, so every feature works without a plan. The plans below are how a public build would be sold.")
            }
        }
    }

    private var yours: some View {
        Section {
            HStack {
                Text("Your plan")
                Spacer()
                Text(store.access.plan.name)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            if let notice {
                Text(notice)
            }
            if let problem = store.problem {
                Text(problem)
                Button("Try again") {
                    Task { await store.loadProducts() }
                }
            }
        } footer: {
            Text("Reading, Guide mode, captions, sound alerts, and everything else that runs on this phone are free and stay free. A plan is only for a model in the cloud or for more than one assistant.")
        }
    }

    private func planSection(_ plan: Plan) -> some View {
        Section {
            ForEach(plan.includes, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
            }
            if store.selling && plan != .free {
                prices(for: plan)
            }
        } header: {
            HStack {
                Text(plan.name)
                if store.selling && store.access.plan == plan {
                    Spacer()
                    Label("Yours", systemImage: "checkmark.circle.fill")
                }
            }
        }
    }

    @ViewBuilder
    private func prices(for plan: Plan) -> some View {
        if store.isLoading {
            ProgressView()
                .accessibilityLabel("Loading prices")
        }
        ForEach(BillingPeriod.allCases, id: \.self) { period in
            let item = PlanProduct(plan: plan, period: period)
            if let product = store.products.first(where: { $0.id == item.id }) {
                Button {
                    Task { await buy(product) }
                } label: {
                    HStack {
                        Text(period == .monthly ? "Monthly" : "Yearly")
                        Spacer()
                        if buying == product.id {
                            ProgressView()
                        } else {
                            Text("\(product.displayPrice) \(period.each)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(buying != nil || restoring)
                .accessibilityLabel("\(plan.name), \(product.displayPrice) \(period.each)")
                .accessibilityHint("Subscribes through the App Store. It renews until you cancel.")
            }
        }
    }

    private var account: some View {
        Section {
            Button {
                Task { await restore() }
            } label: {
                HStack {
                    Text("Restore purchases")
                    if restoring {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(buying != nil || restoring)
            .accessibilityHint("Brings back a plan bought earlier with this Apple Account.")
            if store.access.plan != .free {
                Button("Manage or cancel") {
                    managing = true
                }
                .accessibilityHint("Opens your subscriptions in the App Store.")
            }
            Link("Terms of use", destination: StoreCatalog.termsURL)
            Link("Privacy policy", destination: StoreCatalog.privacyURL)
        } footer: {
            Text("Payment is charged to your Apple Account when you confirm. A plan renews for the same period at the same price until you cancel. You can cancel at any time in your App Store account, at least a day before it renews.")
        }
    }

    // MARK: - Buying

    private func buy(_ product: Product) async {
        buying = product.id
        defer { buying = nil }
        do {
            let result = try await purchase(product)
            let outcome = await store.record(result)
            show(outcome, bought: "Thank you. Your plan is now \(store.access.plan.name).")
        } catch {
            notice = "The purchase did not go through. If you were charged, use Restore purchases."
        }
    }

    private func restore() async {
        restoring = true
        defer { restoring = false }
        let outcome = await store.restore()
        show(outcome, bought: "Restored. Your plan is \(store.access.plan.name).")
    }

    private func show(_ outcome: SubscriptionStore.Outcome, bought: String) {
        switch outcome {
        case .bought:
            notice = bought
        case .waiting:
            notice = "The purchase is waiting for approval. The plan unlocks when it is approved."
        case .cancelled:
            notice = nil
        case .failed(let why):
            notice = why
        }
    }
}

#Preview {
    NavigationStack {
        PlanView()
    }
}
