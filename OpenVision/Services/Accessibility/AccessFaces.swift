// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Saved faces: who they are, when they agreed, and matching a face in view against them.
//
// Everything happens on the phone. Face prints are sealed by AccessStore, are never sent
// anywhere, and are deleted the moment the wearer says to forget someone.

import Foundation

@MainActor
final class AccessFaces: ObservableObject {
    static let shared = AccessFaces()

    @Published private(set) var records: [FaceRecord]

    private static let file = "faces"

    private init() {
        let loaded = AccessStore.load([FaceRecord].self, from: Self.file) ?? []
        records = FaceLedger.pruningExpired(loaded)
        if records.count != loaded.count {
            AccessStore.save(records, to: Self.file)
        }
        // An earlier build kept face prints in a plain file with no record of consent.
        // Those are deleted, not carried over.
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for legacy in ["known_faces_v2.json", "known_faces.json"] {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(legacy))
        }
    }

    /// Drops face prints past the retention window (default 30 days).
    @discardableResult
    func pruneExpired(asOf now: Date = Date()) -> Int {
        let before = records.count
        records = FaceLedger.pruningExpired(records, asOf: now)
        if records.count != before {
            if records.isEmpty { AccessStore.remove(Self.file) } else { AccessStore.save(records, to: Self.file) }
        }
        return before - records.count
    }

    var names: [String] { records.map(\.name) }

    func knows(_ name: String) -> Bool {
        records.contains { $0.name.lowercased() == name.lowercased() }
    }

    /// Saves the one face in the photo under a name. Call only after consent was confirmed.
    func enroll(name: String, jpeg: Data, consentAt: Date) async -> String {
        let faces = await AccessVision.faces(in: jpeg)
        guard let face = faces.first else {
            return "I don't see a face clearly. Ask \(name) to look toward you, then say remember this person as \(name) again."
        }
        guard faces.count == 1 else {
            return "I see \(faces.count) faces, and I need to be sure which one is \(name). Try again with only \(name) in view."
        }
        records = FaceLedger.saving(print: face.featurePrint, for: name, consentAt: consentAt, in: records)
        guard AccessStore.save(records, to: Self.file) else {
            return "I couldn't save \(name)'s face on this phone. Nothing was kept."
        }
        let count = records.first { $0.name.lowercased() == name.lowercased() }?.prints.count ?? 1
        return count > 1
            ? "Added another look at \(name). I'll recognize them better now."
            : "I'll recognize \(name) from now on. Their face data stays on this phone. Say forget \(name)'s face at any time."
    }

    /// Who is in the photo. Returns the spoken answer and the names that were recognized.
    func identify(jpeg: Data) async -> (spoken: String, names: [String]) {
        pruneExpired()
        guard !records.isEmpty else {
            return ("I haven't saved anyone yet. With their permission, say remember this person as, then their name.", [])
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
            AccessStore.save(records, to: Self.file)
        }
        return (FaceLedger.spoken(matches), recognized)
    }

    func forget(name: String) -> String {
        let before = records.count
        records.removeAll { $0.name.lowercased() == name.lowercased() }
        guard records.count < before else { return "I don't have a saved face for \(name)." }
        AccessStore.save(records, to: Self.file)
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
}
