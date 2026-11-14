// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class WearableSessionPhaseTests: XCTestCase {

    func testHappyPathIdleThroughReadyActiveAndBack() {
        var machine = WearableSessionMachine()
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertNoThrow(try machine.transition(to: .registering).get())
        XCTAssertNoThrow(try machine.transition(to: .connecting).get())
        XCTAssertNoThrow(try machine.transition(to: .permissionRequired).get())
        XCTAssertNoThrow(try machine.transition(to: .ready).get())
        XCTAssertNoThrow(try machine.transition(to: .starting).get())
        XCTAssertNoThrow(try machine.transition(to: .active).get())
        XCTAssertNoThrow(try machine.transition(to: .stopping).get())
        XCTAssertNoThrow(try machine.transition(to: .ready).get())
    }

    func testIllegalTransitionIsRejectedWithoutChangingPhase() {
        var machine = WearableSessionMachine(phase: .idle)
        let result = machine.transition(to: .active)
        XCTAssertEqual(machine.phase, .idle)
        guard case .failure(.illegal(from: .idle, to: .active)) = result else {
            return XCTFail("Expected illegal transition error, got \(result)")
        }
    }

    func testEveryPhaseHasANextAction() {
        for phase in WearableSessionPhase.allCases {
            let action = phase.nextAction
            XCTAssertFalse(action.title.isEmpty, "\(phase)")
            XCTAssertFalse(action.detail.isEmpty, "\(phase)")
        }
    }

    func testSideStatesCanRecover() {
        var machine = WearableSessionMachine(phase: .failed)
        XCTAssertNoThrow(try machine.transition(to: .recovering).get())
        XCTAssertNoThrow(try machine.transition(to: .ready).get())

        machine = WearableSessionMachine(phase: .interrupted)
        XCTAssertNoThrow(try machine.transition(to: .recovering).get())
        XCTAssertNoThrow(try machine.transition(to: .ready).get())

        machine = WearableSessionMachine(phase: .unavailable)
        XCTAssertNoThrow(try machine.transition(to: .idle).get())
    }
}
