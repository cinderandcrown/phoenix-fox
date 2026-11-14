// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Saved faces: who they are, when they said yes, and matching a face in view against them.
//
// On-device only. Prints are sealed by AccessStore (encrypted, file protection, no backup),
// never sent anywhere, never created for strangers, and auto-deleted after N days without a
// match. See docs/legal/FACE_RETENTION.md.

import Foundation

@MainActor
final class AccessFaces: ObservableObject {
    static let shared = AccessFaces()

    @Published private(set) var records: [FaceRecord]

    private static let file = "faces"

    private init() {
        let loaded = AccessStore.load([FaceRecord].self, from: Self.file) ?? []
        // Do not touch `self.retentionDays` before `records` is assigned — that property
        // reads SettingsManager and trips "self used before all stored properties".
        let days = FaceRecognitionConsent.clampedRetentionDays(
            SettingsManager.shared.settings.accessibility.faceRetentionDays
        )
        records = FaceLedger.pruningExpired(loaded, retentionDays: days)
        if records.count != loaded.count {
            persist()
        }
        // An earlier build kept face prints in a plain file with no record of consent.
        // Those are deleted, not carried over.
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for legacy in ["known_faces_v2.json", "known_faces.json"] {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(legacy))
        }
    }

    private var retentionDays: Int {
        FaceRecognitionConsent.clampedRetentionDays(
            SettingsManager.shared.settings.accessibility.faceRetentionDays
        )
    }

    /// Drops face prints past the retention window (default 30 days without a match).
    @discardableResult
    func pruneExpired(asOf now: Date = Date()) -> Int {
        let before = records.count
        records = FaceLedger.pruningExpired(records, asOf: now, retentionDays: retentionDays)
        if records.count != before { persist() }
        return before - records.count
    }

    var names: [String] { records.map(\.name) }

    func knows(_ name: String) -> Bool {
        records.contains { $0.name.lowercased() == name.lowercased() }
    }

    /// Saves the one face in the photo under a name. Call only after that person spoke yes.
    func enroll(
        name: String,
        jpeg: Data,
        consentAt: Date,
        consentSource: String = "spoken_yes"
    ) async -> String {
        let faces = await AccessVision.faces(in: jpeg)
        guard let face = faces.first else {
            return "I don't see a face clearly. Ask \(name) to look toward you, then say remember this person as \(name) again."
        }
        guard faces.count == 1 else {
            return "I see \(faces.count) faces, and I need to be sure which one is \(name). Try again with only \(name) in view."
        }
        records = FaceLedger.saving(
            print: face.featurePrint,
            for: name,
            consentAt: consentAt,
            consentSource: consentSource,
            in: records
        )
        guard AccessStore.save(records, to: Self.file) else {
            return "I couldn't save \(name)'s face on this phone. Nothing was kept."
        }
        let count = records.first { $0.name.lowercased() == name.lowercased() }?.prints.count ?? 1
        return count > 1
            ? "Added another look at \(name). I'll recognize them better now."
            : "I'll recognize \(name) from now on. Their face print stays on this phone only. Say forget \(name)'s face at any time."
    }

    /// Who is in the photo. Strangers are reported, never enrolled.
    func identify(jpeg: Data) async -> (spoken: String, names: [String]) {
        pruneExpired()
        guard !records.isEmpty else {
            return ("I haven't saved anyone yet. With their spoken permission, say remember this person as, then their name.", [])
        }
        let faces = await AccessVision.faces(in: jpeg)
        let people = records
        let matches = await Task.detached(priority: .userInitiated) {
            faces.map { FaceLedger.match(distances: AccessVision.distances(from: $0.featurePrint, to: people)) }
        }.value
        var recognized: [String] = []
        for match in matches {
            if case .known(let name) = match { recognized.append(name) }
        }
        if !recognized.isEmpty {
            let now = Date()
            for index in records.indices where recognized.contains(records[index].name) {
                records[index].lastSeen = now
            }
            persist()
        }
        return (FaceLedger.spoken(matches), recognized)
    }

    func forget(name: String) -> String {
        let next = FaceLedger.forgetting(name: name, in: records)
        guard next.count < records.count else { return "I don't have a saved face for \(name)." }
        records = next
        persist()
        return "Done. \(name)'s face data is deleted."
    }

    func forgetAll() -> String {
        records = []
        AccessStore.remove(Self.file)
        return "Done. Every saved face is deleted."
    }

    func listSpoken() -> String {
        names.isEmpty ? "I haven't saved anyone's face." : "I can recognize \(FaceLedger.list(names))."
    }

    private func persist() {
        if records.isEmpty {
            AccessStore.remove(Self.file)
        } else {
            AccessStore.save(records, to: Self.file)
        }
    }
}
