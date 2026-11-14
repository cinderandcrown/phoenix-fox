// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class OwnerProfileSettingsTests: XCTestCase {
    func testAStandardBuildStartsWithTheCautiousDefaults() {
        var settings = AppSettings()
        XCTAssertFalse(OwnerProfile.applyIfNeeded(to: &settings, flavor: .standard))
        XCTAssertEqual(settings, AppSettings())
        XCTAssertFalse(settings.mindMeldEnabled)
        XCTAssertEqual(settings.glasses, GlassesCapabilitySettings())
        XCTAssertEqual(settings.ownerProfileVersion, 0)
    }

    func testTheOwnerBuildTurnsEverythingOn() {
        var settings = AppSettings()
        XCTAssertTrue(OwnerProfile.applyIfNeeded(to: &settings, flavor: .owner))
        XCTAssertTrue(settings.mindMeldEnabled)
        XCTAssertTrue(settings.jarvisLookClip)
        XCTAssertTrue(settings.jarvisFastMode)
        XCTAssertTrue(settings.smartCaptureReceipts)
        XCTAssertTrue(settings.smartCaptureCards)
        XCTAssertTrue(settings.smartCaptureBoards)
        XCTAssertTrue(settings.smartCaptureHighlights)
        XCTAssertTrue(settings.smartCaptureAutoRoute)
        XCTAssertTrue(settings.accessibility.faceRecognition)
        XCTAssertTrue(settings.accessibility.soundAlerts)
        XCTAssertTrue(settings.accessibility.activityRecall)
        XCTAssertTrue(settings.glasses.controls)
        XCTAssertTrue(settings.glasses.fullRateVideo)
        XCTAssertFalse(settings.assistantBots.isEmpty)
        XCTAssertEqual(settings.ownerProfileVersion, OwnerProfile.version)
    }

    func testTheOwnerBuildLeavesTheSafetyNoticeToTheWearer() {
        var settings = AppSettings()
        OwnerProfile.applyIfNeeded(to: &settings, flavor: .owner)
        XCTAssertFalse(settings.accessibility.guideSafetyAccepted)
    }

    func testASwitchTurnedOffAfterwardsStaysOff() {
        var settings = AppSettings()
        OwnerProfile.applyIfNeeded(to: &settings, flavor: .owner)
        settings.mindMeldEnabled = false
        settings.glasses.controls = false
        XCTAssertFalse(OwnerProfile.applyIfNeeded(to: &settings, flavor: .owner))
        XCTAssertFalse(settings.mindMeldEnabled)
        XCTAssertFalse(settings.glasses.controls)
    }

    func testAskingForEverythingAgainTurnsItBackOn() {
        var settings = AppSettings()
        OwnerProfile.applyIfNeeded(to: &settings, flavor: .owner)
        settings.mindMeldEnabled = false
        OwnerProfile.apply(to: &settings)
        XCTAssertTrue(settings.mindMeldEnabled)
    }

    func testTheProfileDoesNotTouchKeysOrTheChosenAssistant() {
        var settings = AppSettings()
        settings.relayToken = "token"
        settings.wakeWord = "Phoenix"
        let backend = settings.aiBackend
        OwnerProfile.applyIfNeeded(to: &settings, flavor: .owner)
        XCTAssertEqual(settings.relayToken, "token")
        XCTAssertEqual(settings.wakeWord, "Phoenix")
        XCTAssertEqual(settings.aiBackend, backend)
    }

    func testSettingsSavedBeforeTheGlassesSwitchesExistedStillLoad() throws {
        // What `SettingsManager.loadSettings` does for an older file: the saved keys laid
        // over the defaults.
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any]
        var merged = try XCTUnwrap(defaults)
        merged.removeValue(forKey: "glasses")
        merged.removeValue(forKey: "ownerProfileVersion")
        merged["glassesMotion"] = true
        merged["wakeWord"] = "Phoenix"
        XCTAssertThrowsError(try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: merged)))

        var overlaid = try XCTUnwrap(defaults)
        for (key, value) in merged { overlaid[key] = value }
        let loaded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: overlaid))
        XCTAssertEqual(loaded.wakeWord, "Phoenix")
        XCTAssertEqual(loaded.glasses, GlassesCapabilitySettings())
        XCTAssertEqual(loaded.ownerProfileVersion, 0)
    }
}
