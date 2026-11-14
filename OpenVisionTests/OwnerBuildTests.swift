// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class OwnerBuildTests: XCTestCase {
    func testOnlyAClearYesMakesAnOwnerBuild() {
        XCTAssertEqual(BuildFlavor(infoValue: "YES"), .owner)
        XCTAssertEqual(BuildFlavor(infoValue: " yes\n"), .owner)
        XCTAssertEqual(BuildFlavor(infoValue: "true"), .owner)
        XCTAssertEqual(BuildFlavor(infoValue: "1"), .owner)
        XCTAssertEqual(BuildFlavor(infoValue: true), .owner)

        XCTAssertEqual(BuildFlavor(infoValue: "NO"), .standard)
        XCTAssertEqual(BuildFlavor(infoValue: false), .standard)
        XCTAssertEqual(BuildFlavor(infoValue: nil), .standard)
        // A build setting nobody set arrives empty, or as the text that was never replaced.
        XCTAssertEqual(BuildFlavor(infoValue: ""), .standard)
        XCTAssertEqual(BuildFlavor(infoValue: "$(PHOENIX_FOX_OWNER_BUILD)"), .standard)
        XCTAssertEqual(BuildFlavor(infoValue: 7), .standard)
    }

    func testOnlyTheOwnerBuildMayUseBetaCapabilities() {
        XCTAssertTrue(BuildFlavor.owner.allowsExperimental)
        XCTAssertFalse(BuildFlavor.standard.allowsExperimental)
    }

    func testGlassesCapabilitiesStartOff() {
        let fresh = GlassesCapabilitySettings()
        XCTAssertFalse(fresh.fullRateVideo)
        XCTAssertFalse(fresh.controls)
        XCTAssertFalse(fresh.captureButton)
        XCTAssertFalse(fresh.headGestures)
        XCTAssertFalse(fresh.highResolutionStills)
        XCTAssertFalse(fresh.ambientAudio)
        XCTAssertFalse(fresh.onGlassesSpeech)
        XCTAssertFalse(fresh.usesSessionWhileEngaged)
        XCTAssertFalse(fresh.usesSessionWhenPhoneIsDeaf)
    }

    func testTheOwnerProfileTurnsOnTheGlassesCapabilities() {
        var glasses = GlassesCapabilitySettings()
        OwnerProfile.apply(to: &glasses)
        XCTAssertTrue(glasses.fullRateVideo)
        XCTAssertTrue(glasses.controls)
        XCTAssertTrue(glasses.captureButton)
        XCTAssertTrue(glasses.headGestures)
        XCTAssertTrue(glasses.highResolutionStills)
        XCTAssertTrue(glasses.ambientAudio)
        XCTAssertTrue(glasses.onGlassesSpeech)
        XCTAssertTrue(glasses.usesSessionWhileEngaged)
    }

    func testOnlySpeechOnTheGlassesOpensASessionWhenJarvisIsNotBusy() {
        var glasses = GlassesCapabilitySettings()
        OwnerProfile.apply(to: &glasses)
        XCTAssertTrue(glasses.onGlassesSpeech)
        XCTAssertTrue(glasses.usesSessionWhenPhoneIsDeaf)

        // One switch gives the touchpad's single tap and long press back to the glasses.
        glasses.onGlassesSpeech = false
        XCTAssertFalse(glasses.usesSessionWhenPhoneIsDeaf)
        XCTAssertTrue(glasses.usesSessionWhileEngaged)
    }

    func testEachControlAloneAsksForTheSessionWhileJarvisIsBusy() {
        for path in [\GlassesCapabilitySettings.controls, \.captureButton, \.headGestures] {
            var glasses = GlassesCapabilitySettings()
            glasses[keyPath: path] = true
            XCTAssertTrue(glasses.usesSessionWhileEngaged)
            XCTAssertFalse(glasses.usesSessionWhenPhoneIsDeaf)
        }
        var other = GlassesCapabilitySettings()
        other.fullRateVideo = true
        other.highResolutionStills = true
        other.ambientAudio = true
        XCTAssertFalse(other.usesSessionWhileEngaged)
    }

    func testAStandardBuildIgnoresSavedBetaSwitches() {
        var saved = GlassesCapabilitySettings()
        OwnerProfile.apply(to: &saved)

        let standard = saved.allowed(in: .standard)
        XCTAssertTrue(standard.fullRateVideo, "Stream sizes and rates are not beta.")
        XCTAssertFalse(standard.controls)
        XCTAssertFalse(standard.captureButton)
        XCTAssertFalse(standard.headGestures)
        XCTAssertFalse(standard.highResolutionStills)
        XCTAssertFalse(standard.ambientAudio)
        XCTAssertFalse(standard.onGlassesSpeech)

        XCTAssertEqual(saved.allowed(in: .owner), saved)
    }

    func testTheOwnerProfileTurnsOnTheAccessibilitySuite() {
        var access = AccessibilitySettings()
        OwnerProfile.apply(to: &access)
        XCTAssertTrue(access.faceRecognition)
        XCTAssertTrue(access.soundAlerts)
        XCTAssertTrue(access.keepTranscripts)
        XCTAssertTrue(access.activityRecall)
        XCTAssertTrue(access.guideCloudDescriptions)
        XCTAssertTrue(access.guideAudioCues)
    }

    func testTheOwnerProfileDoesNotAcceptTheGuideSafetyNoticeForTheWearer() {
        var access = AccessibilitySettings()
        OwnerProfile.apply(to: &access)
        XCTAssertFalse(access.guideSafetyAccepted)
    }

    func testCapabilitiesSavedByAnOlderBuildStillLoad() throws {
        let old = Data(#"{"controls": true, "somethingRemoved": 3}"#.utf8)
        let loaded = try JSONDecoder().decode(GlassesCapabilitySettings.self, from: old)
        XCTAssertTrue(loaded.controls)
        XCTAssertFalse(loaded.ambientAudio)

        var all = GlassesCapabilitySettings()
        OwnerProfile.apply(to: &all)
        let again = try JSONDecoder().decode(GlassesCapabilitySettings.self, from: JSONEncoder().encode(all))
        XCTAssertEqual(again, all)
    }
}
