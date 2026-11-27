// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class PhoenixRigTests: XCTestCase {
    func testOnlyAPrivateHTTPSAddressIsAccepted() {
        XCTAssertEqual(PhoenixRig.baseURL("https://rig.example/v1")?.absoluteString, "https://rig.example/v1")
        XCTAssertEqual(PhoenixRig.baseURL(" https://rig.example:8444/ ")?.absoluteString, "https://rig.example:8444/v1")
        XCTAssertEqual(PhoenixRig.baseURL("https://rig.example/v1///")?.absoluteString, "https://rig.example/v1")
        XCTAssertNil(PhoenixRig.baseURL("http://rig.example/v1"), "frames never cross the network unencrypted")
        XCTAssertNil(PhoenixRig.baseURL("https://user:pass@rig.example/v1"))
        XCTAssertNil(PhoenixRig.baseURL("https://rig.example/v1?key=abc"))
        XCTAssertNil(PhoenixRig.baseURL("rig.example"))
        XCTAssertNil(PhoenixRig.baseURL(""))
    }

    func testTheRigPicksTheModelWhenNoneIsSet() {
        XCTAssertEqual(PhoenixRig.model(""), "phoenix")
        XCTAssertEqual(PhoenixRig.model("  qwen3-vl:8b "), "qwen3-vl:8b")
    }

    func testTheJudgeSendsTheFrameAsAnImage() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let body = try XCTUnwrap(PhoenixRig.judgeBody(jpeg: jpeg, system: "judge", model: "phoenix"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "phoenix")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["content"] as? String, "judge")
        let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        let image = try XCTUnwrap(parts.last?["image_url"] as? [String: Any])
        XCTAssertEqual(image["url"] as? String, "data:image/jpeg;base64," + jpeg.base64EncodedString())
    }

    func testTheReplyTextIsRead() {
        let plain = Data(#"{"choices":[{"message":{"role":"assistant","content":"{\"keep\":true}"}}]}"#.utf8)
        XCTAssertEqual(PhoenixRig.content(from: plain), #"{"keep":true}"#)
        let parts = Data(#"{"choices":[{"message":{"content":[{"type":"text","text":"ok"}]}}]}"#.utf8)
        XCTAssertEqual(PhoenixRig.content(from: parts), "ok")
        XCTAssertNil(PhoenixRig.content(from: Data("not json".utf8)))
    }

    func testAMomentCarriesItsHashAndTime() throws {
        let jpeg = Data("frame".utf8)
        let moment = PhoenixRig.Moment(
            jpeg: jpeg, capturedAt: Date(timeIntervalSince1970: 1_800_000_000), timeZone: "America/Chicago",
            caption: "A receipt.", tags: ["receipt"], action: "receipt"
        )
        // SHA-256 of "frame".
        XCTAssertEqual(moment.sha256, "9dff50df08c635815f4b19da10f756605a34a79a48d4ba48712782502975a70e")
        XCTAssertEqual(moment.camera, "Nick's Eye")
        let body = try XCTUnwrap(PhoenixRig.momentBody(moment))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["sha256"] as? String, moment.sha256)
        XCTAssertEqual(json["image_jpeg_base64"] as? String, jpeg.base64EncodedString())
        XCTAssertEqual(json["captured_at"] as? String, "2027-01-15T02:00:00-06:00")
        XCTAssertEqual(json["time_zone"] as? String, "America/Chicago")
        XCTAssertEqual(json["action"] as? String, "receipt")
    }

    func testAStoredJarvisWakeWordBecomesHeyPhoenix() {
        XCTAssertEqual(WakePhrase.migrated("Jarvis"), "Hey Phoenix")
        XCTAssertEqual(WakePhrase.migrated("Hey Jarvis"), "Hey Phoenix")
        XCTAssertEqual(WakePhrase.migrated("  "), "Hey Phoenix")
        XCTAssertEqual(WakePhrase.migrated("Computer"), "Computer", "a wake word the owner chose stays")
        XCTAssertEqual(AppSettings().wakeWord, "Hey Phoenix")
    }

    func testSmartCaptureNeedsTheRigAndItsKey() {
        var settings = AppSettings()
        XCTAssertFalse(settings.isPhoenixRigConfigured)
        settings.phoenixRigURL = "https://rig.example/v1"
        XCTAssertFalse(settings.isPhoenixRigConfigured)
        settings.phoenixRigKey = "test-key"
        XCTAssertTrue(settings.isPhoenixRigConfigured)
        settings.phoenixRigURL = "http://rig.example/v1"
        XCTAssertFalse(settings.isPhoenixRigConfigured)
    }

    func testTheRigKeyIsKeptInTheKeychain() {
        XCTAssertTrue(SettingsSecrets.fields.map(\.account).contains("phoenixRigKey"))
    }
}
