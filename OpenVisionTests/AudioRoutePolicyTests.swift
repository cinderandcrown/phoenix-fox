// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class AudioRoutePolicyTests: XCTestCase {

    private func snap(hfpIn: Bool = false, hfpOut: Bool = false, a2dp: Bool = false, name: String = "Ray-Ban") -> AudioRouteSnapshot {
        var inputs: [AudioPort] = []
        var outputs: [AudioPort] = []
        var available: [AudioPort] = []
        if hfpIn {
            let port = AudioPort(kind: .bluetoothHFP, name: name)
            inputs.append(port)
            available.append(port)
        }
        if hfpOut { outputs.append(AudioPort(kind: .bluetoothHFP, name: name)) }
        if a2dp { outputs.append(AudioPort(kind: .bluetoothA2DP, name: name)) }
        return AudioRouteSnapshot(inputs: inputs, outputs: outputs, availableInputs: available)
    }

    func testListeningUsesHFPNeverA2DPTogether() {
        let plan = AudioRoutePolicy.plan(
            snapshot: snap(hfpIn: true, hfpOut: true),
            preference: .auto,
            preferGlassesMic: true,
            cameraStreaming: false,
            listening: true
        )
        XCTAssertEqual(plan.link, .hfpConversation)
        XCTAssertTrue(plan.allowHFP)
        XCTAssertFalse(plan.allowA2DP)
        XCTAssertTrue(plan.preferHFPMic)
        XCTAssertGreaterThan(plan.hfpSettleSeconds, 0)
    }

    func testLongPlaybackWithoutListeningUsesA2DPOnly() {
        let plan = AudioRoutePolicy.plan(
            snapshot: snap(hfpIn: true, a2dp: true),
            preference: .auto,
            preferGlassesMic: false,
            cameraStreaming: false,
            listening: false,
            longPlayback: true
        )
        XCTAssertEqual(plan.link, .a2dpPlayback)
        XCTAssertFalse(plan.allowHFP)
        XCTAssertTrue(plan.allowA2DP)
    }

    func testCameraStreamingDropsHFPMic() {
        let plan = AudioRoutePolicy.plan(
            snapshot: snap(hfpIn: true, a2dp: true),
            preference: .auto,
            preferGlassesMic: true,
            cameraStreaming: true,
            listening: true
        )
        XCTAssertEqual(plan.link, .a2dpPlayback)
        XCTAssertFalse(plan.preferHFPMic)
    }

    func testPhonePreferenceForcesPhone() {
        let plan = AudioRoutePolicy.plan(
            snapshot: snap(hfpIn: true, hfpOut: true),
            preference: .phone,
            preferGlassesMic: true,
            cameraStreaming: false
        )
        XCTAssertEqual(plan.link, .phone)
        XCTAssertEqual(plan.destination, .phoneSpeaker)
        XCTAssertTrue(plan.defaultToSpeaker)
    }

    func testCameraMayStartOnlyAfterHFPSettles() {
        XCTAssertFalse(AudioRoutePolicy.cameraMayStart(link: .hfpConversation, hfpSettled: false))
        XCTAssertTrue(AudioRoutePolicy.cameraMayStart(link: .hfpConversation, hfpSettled: true))
        XCTAssertTrue(AudioRoutePolicy.cameraMayStart(link: .a2dpPlayback, hfpSettled: false))
        XCTAssertTrue(AudioRoutePolicy.cameraMayStart(link: .phone, hfpSettled: false))
    }

    func testDestinationNamesTheGlasses() {
        let plan = AudioRoutePolicy.plan(
            snapshot: snap(hfpIn: true, hfpOut: true, name: "Meta Glasses"),
            preference: .auto,
            preferGlassesMic: true,
            cameraStreaming: false
        )
        XCTAssertEqual(plan.destination, .glasses(name: "Meta Glasses", link: .hfpConversation))
        XCTAssertTrue(plan.destination.title.contains("Meta Glasses"))
    }
}
