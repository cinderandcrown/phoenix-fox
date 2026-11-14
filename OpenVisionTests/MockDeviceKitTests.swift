// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// DAT Mock Device Kit integration tests for CI (no physical glasses).
// Meta FAQ: Mock Device Kit does not fully support display glasses — use
// `.metaGlasses` / `.rayBanMeta` for registration, don/doff, and motion feeds.
// Pair `.metaRayBanDisplay` only when previewing MWDATDisplay.

import XCTest
@testable import PhoenixFox

#if canImport(MWDATMockDevice)
import MWDATMockDevice

final class MockDeviceKitTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockDeviceKit.shared.disable()
    }

    override func tearDown() {
        MockDeviceKit.shared.disable()
        super.tearDown()
    }

    func testEnableAndPairMetaGlassesWithoutHardware() throws {
        MockDeviceKit.shared.enable(
            config: MockDeviceKitConfig(initiallyRegistered: true, initialPermissionsGranted: true)
        )
        let device = try MockDeviceKit.shared.pairGlasses(model: .metaGlasses)
        device.powerOn()
        device.unfold()
        device.don()
        XCTAssertFalse(MockDeviceKit.shared.pairedDevices.isEmpty)
        device.doff()
        device.fold()
        device.powerOff()
        MockDeviceKit.shared.unpairDevice(device)
        MockDeviceKit.shared.disable()
    }

    func testPairRayBanMetaForMotionCapableSimulation() throws {
        // Displayless models are the Mock Device Kit path Meta documents for CI.
        // Adventurer maps to `.metaGlasses`; Ray-Ban Meta is the same class.
        MockDeviceKit.shared.enable()
        let device = try MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)
        device.powerOn()
        device.don()
        device.setBatteryLevel(80)
        XCTAssertEqual(MockDeviceKit.shared.pairedDevices.count, 1)
        MockDeviceKit.shared.unpairDevice(device)
    }
}
#else
final class MockDeviceKitTests: XCTestCase {
    func testMockDeviceKitLinkedInCI() throws {
        throw XCTSkip("MWDATMockDevice not available in this test host")
    }
}
#endif
