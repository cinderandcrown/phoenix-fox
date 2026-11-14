// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class HomeModelTests: XCTestCase {
    func testANewModelIsTheFirstLaunch() {
        let model = HomeModel()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.glasses, .notConnected)
        XCTAssertEqual(model.team, .connect)
        XCTAssertNil(model.trouble)
    }

    func testLookToTalkIsNotShownUntilItIsDoingSomething() {
        XCTAssertNil(HomeModel().look)
        XCTAssertTrue(HomeSamples.all.allSatisfy { $0.model.look == nil }, "The first release's screens do not change")
        XCTAssertEqual(HomeSamples.lockedOn.look?.name, "Indy")
        XCTAssertEqual(HomeSamples.lockedOn.look?.title, LookStatus.locked("Indy").title)
        XCTAssertEqual(HomeSamples.lockedOn.look?.symbol, LookStatus.locked("Indy").symbol)
    }

    func testThePhaseFollowsTheSignals() {
        var model = HomeModel()
        model.signals.activity = .listening
        XCTAssertEqual(model.phase, .listening)
        model.signals.activity = .thinking
        model.signals.cameraOn = true
        XCTAssertEqual(model.phase, .looking)
    }

    // MARK: - Samples

    func testTheSamplesHaveUniqueNamesThatAreSafeInAFileName() {
        let names = HomeSamples.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        for name in names {
            XCTAssertTrue(name.allSatisfy { $0.isLetter && $0.isLowercase }, name)
        }
    }

    func testTheSamplesCoverTheFourLiveStates() {
        let phases = Dictionary(uniqueKeysWithValues: HomeSamples.all.map { ($0.name, $0.model.phase) })
        XCTAssertEqual(phases["listening"], .listening)
        XCTAssertEqual(phases["seeing"], .looking)
        XCTAssertEqual(phases["asking"], .asking("Indy"))
        XCTAssertEqual(phases["replying"], .replying)
    }

    func testTheSamplesHoldStill() {
        // A snapshot of a moving orb or a running clock would never match twice.
        for sample in HomeSamples.all {
            XCTAssertEqual(sample.model.fixedTime, 0, sample.name)
            XCTAssertEqual(sample.model.now, HomeSamples.now, sample.name)
        }
    }

    func testTheSampleTeamShowsEveryKindOfStatus() {
        let team = HomeSamples.team
        XCTAssertEqual(team.count, 4)
        XCTAssertEqual(team.filter(\.isWorking).map(\.name), ["Indy"])
        let kinds = team.map { member -> String in
            switch member.status {
            case .ready: return "ready"
            case .working: return "working"
            case .answered: return "answered"
            case .alerted: return "alerted"
            case .failed: return "failed"
            }
        }
        XCTAssertEqual(Set(kinds), ["answered", "working", "alerted", "failed"])
    }

    func testTheCameraSampleShowsTheCameraEverywhere() {
        let model = HomeSamples.seeing
        XCTAssertTrue(model.signals.cameraOn)
        XCTAssertEqual(model.glasses, .cameraOn)
    }
}
