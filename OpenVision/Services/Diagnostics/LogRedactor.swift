// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Strips secrets and bulky media from text before it enters the diagnostics ring
// or a feedback report. The phone redacts; the relay stores what it is given.

import Foundation

enum LogRedactor: Sendable {
    /// Patterns that look like credentials, tokens, or bearer material.
    private static let secretPatterns: [NSRegularExpression] = {
        let sources = [
            #"(?i)\b(authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|bearer|x-api-key|x-webhook-key)\b\s*[:=]\s*["']?[^\s,"']+"#,
            #"(?i)\bBearer\s+[A-Za-z0-9\-._~+/]+=*"#,
            #"\bsk-[A-Za-z0-9]{10,}"#,
            #"\bxai-[A-Za-z0-9]{10,}"#,
            #"\bghp_[A-Za-z0-9]{20,}"#,
            #"\beyJ[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#,
            #"(?i)\b(relay.?token|webhook.?secret|openai|anthropic|grok).{0,20}[:=]\s*["']?[A-Za-z0-9\-._~+/]{12,}"#,
        ]
        return sources.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// Long base64 blobs are almost always audio frames or images.
    private static let base64Blob = try! NSRegularExpression(
        pattern: #"(?:[A-Za-z0-9+/]{80,}={0,2})"#
    )

    static let redactedMarker = "[redacted]"
    static let mediaMarker = "[media omitted]"

    /// Redacts a single log or note line.
    static func redact(_ text: String) -> String {
        var result = text
        let full = NSRange(result.startIndex..., in: result)
        for pattern in secretPatterns {
            result = pattern.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: redactedMarker
            )
        }
        result = base64Blob.stringByReplacingMatches(
            in: result,
            options: [],
            range: NSRange(result.startIndex..., in: result),
            withTemplate: mediaMarker
        )
        _ = full
        return result
    }

    /// Redacts every string leaf in a JSON-compatible tree.
    static func redactJSON(_ value: Any) -> Any {
        switch value {
        case let text as String:
            return redact(text)
        case let list as [Any]:
            return list.map(redactJSON)
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            for (key, child) in dict {
                if isSensitiveKey(key) {
                    out[key] = redactedMarker
                } else {
                    out[key] = redactJSON(child)
                }
            }
            return out
        default:
            return value
        }
    }

    static func isSensitiveKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        let hits = ["token", "secret", "password", "authorization", "api_key", "apikey", "bearer", "cookie"]
        return hits.contains { lower.contains($0) }
    }
}
