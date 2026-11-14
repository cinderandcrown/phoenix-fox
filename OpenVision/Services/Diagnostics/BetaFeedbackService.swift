// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Posts a redacted beta feedback report to the relay, and knows how TestFlight's
// built-in screenshot feedback fits beside it.

import Foundation

enum BetaFeedbackSource: String, Sendable {
    case shake
    case voice
    case settings
    case testflight
}

struct BetaFeedbackReport: Encodable, Sendable {
    var id: String = UUID().uuidString
    var note: String
    var transcript: String
    var source: String
    var appVersion: String
    var build: String
    var includeMedia: Bool
    var diagnostics: [String: JSONValue]

    private enum CodingKeys: String, CodingKey {
        case id, note, transcript, source, diagnostics
        case appVersion = "app_version"
        case build
        case includeMedia = "include_media"
    }
}

enum BetaFeedbackService {
    /// True when this install looks like TestFlight (sandbox receipt).
    static var isTestFlightInstall: Bool {
        guard let url = Bundle.main.appStoreReceiptURL else { return false }
        return url.lastPathComponent == "sandboxReceipt"
    }

    /// Tip shown next to our own reporter — TestFlight already captures screenshots.
    static var testFlightTip: String {
        if isTestFlightInstall {
            return "This is a TestFlight build. Taking a screenshot also opens Apple’s feedback sheet — use that for annotated screenshots. Shake or say “Jarvis, report a bug” to send structured diagnostics through your relay."
        }
        return "On a TestFlight build, taking a screenshot opens Apple’s feedback sheet for annotated screenshots. Structured diagnostics still go through your relay."
    }

    @MainActor
    static func makeReport(
        note: String,
        transcript: String,
        source: BetaFeedbackSource,
        includeMedia: Bool,
        settings: AppSettings,
        glasses: GlassesManager
    ) -> BetaFeedbackReport {
        let diagnostics = DiagnosticsSnapshot.build(
            settings: settings,
            glasses: glasses,
            includeMedia: includeMedia
        )
        return BetaFeedbackReport(
            note: String(note.prefix(8000)),
            transcript: String(transcript.prefix(16000)),
            source: source.rawValue,
            appVersion: Config.appVersion,
            build: Config.buildNumber,
            includeMedia: includeMedia,
            diagnostics: JSONValue.object(from: diagnostics)
        )
    }

    static func submit(_ report: BetaFeedbackReport, to endpoint: RelayEndpoint, client: RelayClient = RelayClient()) async throws -> String {
        try await client.submitFeedback(report, to: endpoint)
    }
}

// MARK: - JSONValue bridge for arbitrary diagnostics trees

enum JSONValue: Encodable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    static func object(from dictionary: [String: Any]) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (key, value) in dictionary {
            out[key] = JSONValue(value)
        }
        return out
    }

    init(_ value: Any) {
        switch value {
        case let text as String:
            self = .string(LogRedactor.redact(text))
        case let number as NSNumber:
            // Bool is an NSNumber on Apple platforms.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int:
            self = .number(Double(int))
        case let double as Double:
            self = .number(double)
        case let dict as [String: Any]:
            self = .object(Self.object(from: dict))
        case let list as [Any]:
            self = .array(list.map(JSONValue.init))
        default:
            self = .string(LogRedactor.redact(String(describing: value)))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
