// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class OnDeviceLookTests: XCTestCase {

    func testReadRequestsPreferOCR() {
        XCTAssertEqual(LookKindParser.kind(for: "what does this say"), .readText)
        XCTAssertEqual(LookKindParser.kind(for: "Read this label please"), .readText)
        XCTAssertTrue(OnDeviceLook.textIsEnough(kind: .readText, fragments: ["Aspirin 81 mg"]))
        XCTAssertFalse(OnDeviceLook.textIsEnough(kind: .describeScene, fragments: ["Aspirin 81 mg"]))
        XCTAssertEqual(OnDeviceLook.spokenText(from: ["Hello"]), "It says: Hello")
    }

    func testBarcodeAndSceneSpokenLines() {
        XCTAssertEqual(LookKindParser.kind(for: "scan this QR code"), .code)
        XCTAssertEqual(OnDeviceLook.spokenCode(from: ["https://example.com"]), "The code says: https://example.com")
        XCTAssertNil(OnDeviceLook.spokenCode(from: []))
        XCTAssertEqual(
            OnDeviceLook.spokenScene(from: [("desk", 0.9), ("laptop_computer", 0.8)]),
            "I see desk, and laptop computer."
        )
    }

    func testUnchangedSceneUsesFrameChange() {
        let a = [UInt8](repeating: 40, count: 64)
        XCTAssertFalse(OnDeviceLook.isUnchanged(previousThumb: nil, currentThumb: a))
        XCTAssertTrue(OnDeviceLook.isUnchanged(previousThumb: a, currentThumb: a))
        var b = a
        for i in 0..<32 { b[i] = 200 }
        XCTAssertFalse(OnDeviceLook.isUnchanged(previousThumb: a, currentThumb: b))
    }
}

final class OfflineCapabilityTests: XCTestCase {

    func testMatrixMarksCloudOnlyRows() {
        XCTAssertFalse(CapabilityMatrix.rows.isEmpty)
        XCTAssertTrue(CapabilityMatrix.offlineRows.contains { $0.id == "wake" })
        XCTAssertTrue(CapabilityMatrix.offlineRows.contains { $0.id == "ocr" })
        XCTAssertTrue(CapabilityMatrix.cloudOnlyRows.contains { $0.id == "bots" })
        XCTAssertTrue(CapabilityMatrix.offlineRefusal(for: "bots").contains("connection"))
    }

    func testOfflineGateBlocksCloudWhenOffline() {
        XCTAssertFalse(OfflineGate.mayUseCloud(rowId: "bots", path: .offline))
        XCTAssertTrue(OfflineGate.mayUseCloud(rowId: "bots", path: .online))
        XCTAssertTrue(OfflineGate.mayUseCloud(rowId: "ocr", path: .offline))
        XCTAssertTrue(OfflineGate.shouldPreferOnDevice(kind: .readText, path: .online))
    }

    func testOfflineIndicatorCopy() {
        XCTAssertEqual(NetworkPathStatus.offline.title, "Offline mode")
        XCTAssertTrue(NetworkPathStatus.offline.spoken.contains("Wake word"))
    }
}

final class ProviderEfficiencyTests: XCTestCase {

    func testVisionNeedNeverMapsToInstantRole() {
        XCTAssertEqual(TurnClassifier.need(for: "what am I looking at"), .vision)
        XCTAssertEqual(TurnClassifier.role(for: .vision), .vision)
        XCTAssertEqual(TurnClassifier.need(for: "what time is it"), .local)
        XCTAssertNil(TurnClassifier.role(for: .local))
        XCTAssertEqual(TurnClassifier.role(for: .reason), .top)
    }

    func testCatalogNeverGivesTopTheInstantId() {
        let catalog = ModelCatalog()
        XCTAssertNotEqual(catalog.model(for: .grok, role: .top), catalog.model(for: .grok, role: .instant))
        XCTAssertEqual(catalog.model(for: .grok, role: .vision), catalog.grok.vision)
    }

    func testContextTrimKeepsTheTailAndShortensLongTurns() {
        let turns = (0..<20).map { (role: $0 % 2 == 0 ? "user" : "assistant", content: String(repeating: "a", count: 50) + "\($0)") }
        let trimmed = ContextBudget.trim(turns, maxMessages: 4, maxChars: 20)
        XCTAssertEqual(trimmed.count, 4)
        XCTAssertTrue(trimmed.last!.content.contains("19") || trimmed.last!.content.contains("..."))
    }

    func testUsageLedgerSoftCap() {
        var ledger = ProviderUsageLedger()
        ledger.monthlySoftCapDollars = 1
        ledger.record(.grok, inputTokens: 100_000, outputTokens: 100_000, tenthsOfCent: 1_500)
        XCTAssertTrue(ledger.softCapReached)
        XCTAssertEqual(ledger.grok.requests, 1)
    }
}
