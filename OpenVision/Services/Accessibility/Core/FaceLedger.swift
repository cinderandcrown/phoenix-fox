// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The rules for recognizing saved contacts by face.
//
// A face is saved only after the wearer confirms that the person agreed, and the date of
// that confirmation is stored with it. Recognition answers with a name only when one saved
// person is clearly the closest match. Naming the wrong person is worse than naming no
// one, so a close call is reported as "not sure".

import Foundation

struct FaceRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    /// When the wearer confirmed this person agreed to be remembered.
    var consentAt: Date
    /// Face prints from the vision system. Several, taken at different times, match better
    /// than one. They are opaque here and never leave the phone.
    var prints: [Data]
    var lastSeen: Date?

    init(name: String, consentAt: Date, prints: [Data]) {
        id = UUID()
        self.name = name
        self.consentAt = consentAt
        self.prints = prints
    }
}

enum FaceLedger {
    /// The most prints kept for one person. The oldest is dropped when another is added.
    static let printsPerPerson = 5

    enum Match: Equatable, Sendable {
        case known(name: String)
        /// A saved person is near, but not clearly nearer than everyone else.
        case unsure
        case stranger
    }

    /// Picks the person for one face in view.
    ///
    /// - Parameters:
    ///   - distances: For each saved person, the smallest distance between the face in view
    ///     and any of that person's prints. Smaller is more alike.
    ///   - limit: A distance above this is not a match at all.
    ///   - margin: The best match must beat the runner-up by at least this much.
    static func match(distances: [(name: String, distance: Float)], limit: Float = 0.5, margin: Float = 0.04) -> Match {
        let ranked = distances.sorted { $0.distance < $1.distance }
        guard let best = ranked.first, best.distance <= limit else { return .stranger }
        if ranked.count > 1, ranked[1].distance - best.distance < margin { return .unsure }
        return .known(name: best.name)
    }

    /// What to say for the faces in one photo.
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

    /// Adds a print to a person, creating the record on first use. Returns the new list.
    static func saving(print: Data, for name: String, consentAt: Date, in records: [FaceRecord]) -> [FaceRecord] {
        var records = records
        if let index = records.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            records[index].prints.append(print)
            if records[index].prints.count > printsPerPerson {
                records[index].prints.removeFirst(records[index].prints.count - printsPerPerson)
            }
            records[index].consentAt = consentAt
        } else {
            records.append(FaceRecord(name: name, consentAt: consentAt, prints: [print]))
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
