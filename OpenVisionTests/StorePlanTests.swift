// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class StorePlanTests: XCTestCase {
    private let terms = URL(string: "https://example.com/terms")
    private let privacy = URL(string: "https://example.com/privacy")

    // MARK: - Plans

    func testEachPlanHoldsThePlansBelowIt() {
        XCTAssertEqual(Plan.allCases.sorted(), [.free, .ownAI, .includedAI, .botTeam])
        XCTAssertLessThan(Plan.free, Plan.ownAI)
        XCTAssertLessThan(Plan.includedAI, Plan.botTeam)
    }

    func testEachPaidFeatureNamesItsCheapestPlan() {
        XCTAssertEqual(PaidFeature.ownKeyAI.plan, .ownAI)
        XCTAssertEqual(PaidFeature.includedAI.plan, .includedAI)
        XCTAssertEqual(PaidFeature.botTeam.plan, .botTeam)
    }

    func testARefusalNamesThePlanAndSaysWhatStillWorks() {
        for feature in PaidFeature.allCases {
            XCTAssertTrue(feature.refusal.contains(feature.plan.name), feature.refusal)
            XCTAssertTrue(feature.refusal.contains("Settings, then Plan"), feature.refusal)
            XCTAssertTrue(feature.refusal.contains("still work"), feature.refusal)
        }
    }

    func testTheFreePlanListsTheAccessibilitySuite() {
        let free = Plan.free.includes.joined(separator: " ")
        for word in ["accessibility suite", "Guide mode", "reading", "captions", "emergency contact"] {
            XCTAssertTrue(free.contains(word), word)
        }
    }

    // MARK: - What a plan allows

    func testABuildThatSellsNothingAllowsEverything() {
        for feature in PaidFeature.allCases {
            XCTAssertTrue(Access.everything.allows(feature))
            XCTAssertTrue(Access(selling: false, plan: .free).allows(feature))
        }
    }

    func testAPlanAllowsItsOwnFeaturesAndThoseBelow() {
        let free = Access(selling: true, plan: .free)
        XCTAssertFalse(free.allows(.ownKeyAI))
        XCTAssertFalse(free.allows(.includedAI))
        XCTAssertFalse(free.allows(.botTeam))

        let own = Access(selling: true, plan: .ownAI)
        XCTAssertTrue(own.allows(.ownKeyAI))
        XCTAssertFalse(own.allows(.includedAI))
        XCTAssertFalse(own.allows(.botTeam))

        let included = Access(selling: true, plan: .includedAI)
        XCTAssertTrue(included.allows(.ownKeyAI))
        XCTAssertTrue(included.allows(.includedAI))
        XCTAssertFalse(included.allows(.botTeam))

        let team = Access(selling: true, plan: .botTeam)
        for feature in PaidFeature.allCases { XCTAssertTrue(team.allows(feature)) }
    }

    func testTheBrainsOnThePhoneNeedNoPlan() {
        XCTAssertNil(AIBackendType.appleFoundation.paidFeature)
        XCTAssertNil(AIBackendType.localGemma.paidFeature)
        let cloud = AIBackendType.allCases.filter { $0 != .appleFoundation && $0 != .localGemma }
        XCTAssertFalse(cloud.isEmpty)
        for brain in cloud {
            XCTAssertEqual(brain.paidFeature, .ownKeyAI, brain.rawValue)
        }
    }

    // MARK: - The catalog

    func testProductIdentifiersNeverChange() {
        // These are typed into App Store Connect by hand. A product identifier cannot be
        // renamed or reused there, so a change here would orphan every subscriber.
        XCTAssertEqual(PlanProduct(plan: .ownAI, period: .monthly).id, "com.cinderandcrown.phoenixfox.plan.ownai.monthly")
        XCTAssertEqual(PlanProduct(plan: .ownAI, period: .yearly).id, "com.cinderandcrown.phoenixfox.plan.ownai.yearly")
        XCTAssertEqual(PlanProduct(plan: .includedAI, period: .monthly).id, "com.cinderandcrown.phoenixfox.plan.includedai.monthly")
        XCTAssertEqual(PlanProduct(plan: .includedAI, period: .yearly).id, "com.cinderandcrown.phoenixfox.plan.includedai.yearly")
        XCTAssertEqual(PlanProduct(plan: .botTeam, period: .monthly).id, "com.cinderandcrown.phoenixfox.plan.botteam.monthly")
        XCTAssertEqual(PlanProduct(plan: .botTeam, period: .yearly).id, "com.cinderandcrown.phoenixfox.plan.botteam.yearly")
    }

    func testAnIdentifierReadsBackToItsProduct() {
        for plan in Plan.allCases where plan != .free {
            for period in BillingPeriod.allCases {
                let product = PlanProduct(plan: plan, period: period)
                XCTAssertEqual(StoreCatalog.product(id: product.id), product)
            }
        }
    }

    func testAnythingElseIsNotAProduct() {
        let strangers = [
            "",
            "com.cinderandcrown.phoenixfox.plan.",
            "com.cinderandcrown.phoenixfox.plan.free.monthly",
            "com.cinderandcrown.phoenixfox.plan.ownai",
            "com.cinderandcrown.phoenixfox.plan.ownai.weekly",
            "com.cinderandcrown.phoenixfox.plan.ownai.monthly.extra",
            "com.cinderandcrown.phoenixfox.plan..monthly",
            "com.example.plan.ownai.monthly",
            "ownai.monthly",
        ]
        for id in strangers {
            XCTAssertNil(StoreCatalog.product(id: id), id)
        }
    }

    func testIncludedAIIsNotSoldUntilThereIsAServiceBehindIt() {
        XCTAssertFalse(StoreCatalog.hostedAIReady)
        XCTAssertEqual(StoreCatalog.plansOnSale(hostedAI: false), [.ownAI, .botTeam])
        XCTAssertEqual(StoreCatalog.plansOnSale(hostedAI: true), [.ownAI, .includedAI, .botTeam])
        XCTAssertEqual(StoreCatalog.products(hostedAI: false).count, 4)
        XCTAssertEqual(StoreCatalog.products(hostedAI: true).count, 6)
        XCTAssertFalse(StoreCatalog.products(hostedAI: false).contains { $0.plan == .includedAI })
    }

    func testTheBestPlanHeldWins() {
        let own = PlanProduct(plan: .ownAI, period: .yearly).id
        let team = PlanProduct(plan: .botTeam, period: .monthly).id
        XCTAssertEqual(StoreCatalog.plan(owning: []), .free)
        XCTAssertEqual(StoreCatalog.plan(owning: [own]), .ownAI)
        XCTAssertEqual(StoreCatalog.plan(owning: [own, team]), .botTeam)
        XCTAssertEqual(StoreCatalog.plan(owning: [team, own]), .botTeam)
        XCTAssertEqual(StoreCatalog.plan(owning: ["com.example.other", own]), .ownAI)
        XCTAssertEqual(StoreCatalog.plan(owning: ["com.example.other"]), .free)
    }

    func testAPlanBoughtBeforeItLeftTheShelfIsStillHonoured() {
        let included = PlanProduct(plan: .includedAI, period: .monthly).id
        XCTAssertFalse(StoreCatalog.products(hostedAI: false).map(\.id).contains(included))
        XCTAssertEqual(StoreCatalog.plan(owning: [included]), .includedAI)
    }

    // MARK: - The switch

    func testTheOwnerBuildNeverSells() {
        for value: Any? in ["YES", true, "1", "NO", nil] {
            XCTAssertFalse(StoreSwitch.isOn(flavor: .owner, infoValue: value, missing: []))
        }
    }

    func testAStandardBuildSellsOnlyOnAClearYes() {
        XCTAssertTrue(StoreSwitch.isOn(flavor: .standard, infoValue: "YES", missing: []))
        XCTAssertTrue(StoreSwitch.isOn(flavor: .standard, infoValue: true, missing: []))
        XCTAssertFalse(StoreSwitch.isOn(flavor: .standard, infoValue: "NO", missing: []))
        XCTAssertFalse(StoreSwitch.isOn(flavor: .standard, infoValue: nil, missing: []))
        XCTAssertFalse(StoreSwitch.isOn(flavor: .standard, infoValue: "", missing: []))
        XCTAssertFalse(StoreSwitch.isOn(flavor: .standard, infoValue: "$(PHOENIX_FOX_STORE)", missing: []))
    }

    func testNothingIsSoldWhileTheSellingScreenIsIncomplete() {
        XCTAssertEqual(StoreCatalog.missingBeforeSale(terms: terms, privacy: privacy), [])
        XCTAssertEqual(StoreCatalog.missingBeforeSale(terms: terms, privacy: nil), ["the privacy policy"])
        XCTAssertEqual(StoreCatalog.missingBeforeSale(terms: nil, privacy: nil), ["the terms of use", "the privacy policy"])
        XCTAssertFalse(StoreSwitch.isOn(flavor: .standard, infoValue: "YES", missing: ["the privacy policy"]))
    }

    func testTheStoreIsOffTodayEvenIfTheSettingIsYes() {
        // No privacy policy is published yet. Give `StoreCatalog.privacyURL` an address and
        // change this test in the same commit.
        XCTAssertNil(StoreCatalog.privacyURL)
        XCTAssertNotNil(StoreCatalog.termsURL)
        XCTAssertFalse(StoreSwitch.isOn(flavor: .standard, infoValue: "YES"))
    }

    // MARK: - More than one assistant

    private func route(_ text: String, covered: Bool) -> JarvisRoute {
        FastModeRouter.rules(text, context: FastModeRouter.Context(
            fastMode: false,
            isPro: covered,
            bots: AssistantRoster.seed,
            instantReady: false,
            clipEnabled: false
        ))
    }

    func testASecondAssistantNeedsTheBotTeamPlan() {
        XCTAssertEqual(route("ask Indy about the invoice", covered: false), .needsPro(PaidFeature.botTeam.refusal))
        XCTAssertEqual(route("all hands", covered: false), .needsPro(PaidFeature.botTeam.refusal))
        if case .needsPro = route("ask Indy about the invoice", covered: true) { XCTFail("The plan covers it.") }
        if case .needsPro = route("all hands", covered: true) { XCTFail("The plan covers it.") }
    }

    func testTheFirstAssistantNeverNeedsTheBotTeamPlan() {
        for text in ["what's the weather", "ask Fire Fox about the invoice", "brief me", "take a note buy milk"] {
            if case .needsPro = route(text, covered: false) { XCTFail(text) }
        }
    }
}
