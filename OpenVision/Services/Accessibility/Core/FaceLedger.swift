// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The rules for recognizing saved contacts by face.
//
// A face is saved only after that person says yes (spoken consent, timestamped). Strangers
// are never stored. Prints expire after N days without a match (default 30, min 1).
// See docs/legal/FACE_RETENTION.md.

import Foundation

struct FaceRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    /// When the person said yes to enrollment (spoken biometric consent).
    var consentAt: Date
    /// How consent was captured (always spoken yes for new enrollments).
    var consentSource: String
    /// Face prints from the vision system. Opaque; never leave the phone.
    var prints: [Data]
    /// Last successful match. Retention is measured from this (or consentAt if never matched).
    var lastSeen: Date?

    init(
        name: String,
        consentAt: Date,
        prints: [Data],
        consentSource: String = "spoken_yes",
        lastSeen: Date? = nil
    ) {
        id = UUID()
        self.name = name
        self.consentAt = consentAt
        self.consentSource = consentSource
        self.prints = prints
        self.lastSeen = lastSeen
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        consentAt = try values.decode(Date.self, forKey: .consentAt)
        consentSource = try values.decodeIfPresent(String.self, forKey: .consentSource) ?? "spoken_yes"
        prints = try values.decode([Data].self, forKey: .prints)
        lastSeen = try values.decodeIfPresent(Date.self, forKey: .lastSeen)
    }

    /// Anchor for auto-delete: last match, else enrollment consent.
    var retentionAnchor: Date { lastSeen ?? consentAt }
}

enum FaceLedger {
    /// The most prints kept for one person. The oldest is dropped when another is added.
    static let printsPerPerson = 5

    /// Default days without a match before auto-delete (Nicholas / FACE_RETENTION.md).
    static let defaultRetentionDays = 30

    enum Match: Equatable, Sendable {
        case known(name: String)
        /// A saved person is near, but not clearly nearer than everyone else.
        case unsure
        case stranger
    }

    /// Picks the person for one face in view.
    static func match(distances: [(name: String, distance: Float)], limit: Float = 0.5, margin: Float = 0.04) -> Match {
        let ranked = distances.sorted { $0.distance < $1.distance }
        guard let best = ranked.first, best.distance <= limit else { return .stranger }
        if ranked.count > 1, ranked[1].distance - best.distance < margin { return .unsure }
        return .known(name: best.name)
    }

    /// What to say for the faces in one photo. Strangers are named as unknown — never enrolled here.
    static func spoken(_ matches: [Match]) -> String {
        guard !matches.isEmpty else { return "I don't see a face. Ask them to look toward you and try again." }
        let names = matches.compactMap { match -> String? in
            if case .known(let name) = match { return name }
            return nil
        }
        let others = matches.count - names.count
        let unsure = matches.contains(.unsure)
        if names.isEmpty {
            let who = matches.count == 1 ? "this is" : "these people are"
            return unsure
                ? "I'm not sure who \(who). It might be someone you saved, but I won't guess."
                : "I don't recognize \(matches.count == 1 ? "this person" : "anyone here")."
        }
        var line = "This looks like \(list(names))."
        if others == 1 { line += " There is one more person I don't recognize." }
        if others > 1 { line += " There are \(others) more people I don't recognize." }
        return line
    }

    /// Drops records with no match (or consent) within `retentionDays`. Pure for unit tests.
    static func pruningExpired(
        _ records: [FaceRecord],
        asOf now: Date = Date(),
        retentionDays: Int = defaultRetentionDays
    ) -> [FaceRecord] {
        let days = FaceRecognitionConsent.clampedRetentionDays(retentionDays)
        let limit = TimeInterval(days) * 24 * 60 * 60
        return records.filter { now.timeIntervalSince($0.retentionAnchor) < limit }
    }

    /// Removes one person by name (case-insensitive). Returns the new list.
    static func forgetting(name: String, in records: [FaceRecord]) -> [FaceRecord] {
        records.filter { $0.name.lowercased() != name.lowercased() }
    }

    /// Adds a print after spoken consent. Never called for strangers / passive sightings.
    static func saving(
        print: Data,
        for name: String,
        consentAt: Date,
        consentSource: String = "spoken_yes",
        in records: [FaceRecord]
    ) -> [FaceRecord] {
        var records = records
        if let index = records.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            records[index].prints.append(print)
            if records[index].prints.count > printsPerPerson {
                records[index].prints.removeFirst(records[index].prints.count - printsPerPerson)
            }
            records[index].consentAt = consentAt
            records[index].consentSource = consentSource
        } else {
            records.append(FaceRecord(
                name: name,
                consentAt: consentAt,
                prints: [print],
                consentSource: consentSource
            ))
        }
        return records
    }

    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + ", and " + (names.last ?? "")
        }
    }
}
