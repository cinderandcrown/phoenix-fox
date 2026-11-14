// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Deciding what a look needs before a frame leaves the phone.
//
// Many "what does this say" / "read this" requests are answered by OCR alone. Sending the
// image to a paid vision model would cost more and add latency for the same answer. A
// scene that has not changed since the last look can also be skipped. The rules are here,
// without Vision or the network, so they can be tested.

import Foundation

/// What a look asked for, after reading the wearer's words.
enum LookKind: Equatable, Sendable {
    /// Read the printed words. OCR on the phone is enough when it finds text.
    case readText
    /// Name what is in view. Needs a scene model (on-device or cloud).
    case describeScene
    /// Who is in view. Uses on-device face prints when people are saved.
    case who
    /// A barcode or QR. On-device barcode detection is enough when one is found.
    case code
}

enum LookKindParser {
    private static let read = [
        "what does this say", "read this", "read that", "read the label",
        "read the sign", "translate this", "what's written", "whats written",
        "what is written", "spell this",
    ]
    private static let who = ["who is this", "who's this", "whos this", "who is that", "who's that", "do you recognize"]
    private static let code = ["scan this", "scan the code", "what's the barcode", "whats the barcode", "qr code"]

    static func kind(for prompt: String) -> LookKind {
        let lower = prompt.lowercased()
        if read.contains(where: { lower.contains($0) }) { return .readText }
        if who.contains(where: { lower.contains($0) }) { return .who }
        if code.contains(where: { lower.contains($0) }) { return .code }
        return .describeScene
    }
}

/// The result of trying to answer on the phone before a cloud call.
enum OnDeviceLookResult: Equatable, Sendable {
    /// Spoken answer, ready to say. No cloud call.
    case answered(String)
    /// Not enough on the phone; send a budgeted JPEG to a vision model.
    case needsVision
    /// The view has not changed since the last look; say so or reuse the last answer.
    case unchanged(lastAnswer: String?)
}

/// Pure rules for OCR-first and nothing-changed. The Vision calls live at the call site.
enum OnDeviceLook {
    /// Whether OCR text alone answers this kind of look.
    static func textIsEnough(kind: LookKind, fragments: [String]) -> Bool {
        guard kind == .readText else { return false }
        let joined = fragments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let chars = joined.joined(separator: " ").count
        return chars >= 3
    }

    /// Spoken line from OCR fragments.
    static func spokenText(from fragments: [String]) -> String {
        let lines = fragments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.isEmpty { return "I couldn't read any text." }
        if lines.count == 1 { return "It says: \(lines[0])" }
        return "It says: " + lines.prefix(8).joined(separator: ". ")
    }

    /// Spoken line from barcode payloads.
    static func spokenCode(from payloads: [String]) -> String? {
        let clean = payloads.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let first = clean.first else { return nil }
        if clean.count == 1 { return "The code says: \(first)" }
        return "I found \(clean.count) codes. The first says: \(first)"
    }

    /// Spoken line from on-device scene labels (VNClassify-style identifiers).
    static func spokenScene(from labels: [(name: String, confidence: Double)], minimum: Double = 0.35) -> String? {
        let kept = labels.filter { $0.confidence >= minimum }.prefix(3)
        guard !kept.isEmpty else { return nil }
        let names = kept.map(\.name).map(friendlyName)
        if names.count == 1 { return "I see \(names[0])." }
        return "I see " + names.dropLast().joined(separator: ", ") + ", and \(names.last!)."
    }

    /// Whether the view is the same as the last look.
    static func isUnchanged(previousThumb: [UInt8]?, currentThumb: [UInt8]) -> Bool {
        guard let previousThumb, !previousThumb.isEmpty else { return false }
        return !FrameChange.isNewScene(previousThumb, currentThumb)
    }

    private static func friendlyName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").lowercased()
    }
}
