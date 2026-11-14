// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class WornPostureTests: XCTestCase {
    private typealias Vector = HeadMotion.Vector

    func testLevelWhenGravityIsDown() {
        var tracker = WornPostureTracker()
        var context: WornPostureContext?
        for step in 0..<20 {
            let t = Double(step) / 30
            context = tracker.take(
                HeadMotion(time: t, turning: .zero, acceleration: Vector(x: 0, y: -9.81, z: 0)),
                worn: true
            ) ?? context
        }
        XCTAssertEqual(context?.posture, .level)
        XCTAssertEqual(context?.worn, true)
    }

    func testLookingDownSettles() {
        var tracker = WornPostureTracker()
        // Tip forward: more gravity on −Z.
        let accel = Vector(x: 0, y: -6, z: -7)
        var context: WornPostureContext?
        for step in 0..<30 {
            context = tracker.take(
                HeadMotion(time: Double(step) / 30, turning: .zero, acceleration: accel),
                worn: true
            ) ?? context
        }
        XCTAssertEqual(context?.posture, .lookingDown)
        XCTAssertLessThan(context?.pitchDegrees ?? 0, 0)
    }

    func testLookingUpSettles() {
        var tracker = WornPostureTracker()
        // Tip back: more gravity on +Z.
        let accel = Vector(x: 0, y: -6, z: 7)
        var context: WornPostureContext?
        for step in 0..<30 {
            context = tracker.take(
                HeadMotion(time: Double(step) / 30, turning: .zero, acceleration: accel),
                worn: true
            ) ?? context
        }
        XCTAssertEqual(context?.posture, .lookingUp)
        XCTAssertGreaterThan(context?.pitchDegrees ?? 0, 0)
    }

    func testDoffClearsPosture() {
        var tracker = WornPostureTracker()
        _ = tracker.take(
            HeadMotion(time: 1, turning: .zero, acceleration: Vector(x: 0, y: -9.81, z: 0)),
            worn: true
        )
        let off = tracker.take(
            HeadMotion(time: 2, turning: .zero, acceleration: Vector(x: 0, y: -9.81, z: 0)),
            worn: false
        )
        XCTAssertEqual(off?.worn, false)
        XCTAssertEqual(off?.posture, .unknown)
    }
}

final class SessionResumeStoreTests: XCTestCase {
    func testOffersWhenLevelAndWorn() {
        var store = SessionResumeStore()
        store.remember(title: "Walk inbox", detail: "3 left", at: 1)
        XCTAssertNil(store.offer(on: WornPostureContext(worn: true, posture: .lookingDown, pitchDegrees: -40, updatedAt: 2)))
        let offer = store.offer(on: WornPostureContext(worn: true, posture: .level, pitchDegrees: 0, updatedAt: 3))
        XCTAssertEqual(offer?.title, "Walk inbox")
        XCTAssertNil(store.offer(on: WornPostureContext(worn: true, posture: .level, pitchDegrees: 0, updatedAt: 4)))
    }
}

final class InboxWalkGestureTests: XCTestCase {
    func testNodActsAndShakeSkips() {
        var walk = InboxWalkController(items: [
            InboxWalkItem(id: "1", spokenSummary: "Sam about dinner"),
            InboxWalkItem(id: "2", spokenSummary: "Lease renewal"),
        ])
        XCTAssertEqual(walk.headAnswerPolicy, .yesOrNo)
        let first = walk.take(.yes)
        XCTAssertEqual(first?.action, .act)
        XCTAssertEqual(first?.item.id, "1")
        let second = walk.take(.no)
        XCTAssertEqual(second?.action, .skip)
        XCTAssertEqual(second?.item.id, "2")
        XCTAssertFalse(walk.isActive)
        XCTAssertEqual(walk.headAnswerPolicy, .none)
    }
}

final class CompanionCardTests: XCTestCase {
    func testRoundTripHudKind() {
        let card = CompanionCard(kind: .alert, bot: "Driver", text: "Gate is open", actions: ["dismiss"])
        let hud = card.asHudCard()
        XCTAssertEqual(hud.kind, .alert)
        XCTAssertEqual(hud.bot, "Driver")
        let back = CompanionCard.from(hud: hud)
        XCTAssertEqual(back.kind, .alert)
        XCTAssertEqual(back.text, "Gate is open")
    }

    func testCodableSchemaStableForWebApp() throws {
        let card = CompanionCard(kind: .inboxItem, bot: "Fire Fox", text: "Sam about dinner", bullets: ["2 min ago"], actions: ["act", "skip"])
        let data = try JSONEncoder().encode(card)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("inboxItem") || json.contains("inbox_item") || json.contains("\"kind\""))
        let decoded = try JSONDecoder().decode(CompanionCard.self, from: data)
        XCTAssertEqual(decoded, card)
    }
}
