// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Structured logger for beta diagnostics.
//
// Writes to OSLog with privacy annotations, and keeps a short redacted ring of recent
// lines for shake-to-report / "Jarvis, report a bug". Never stores raw audio or images.

import Foundation
import OSLog

enum FoxLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.cinderandcrown.phoenixfox"

    static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    /// Public operational detail — safe for Console.app without a debugger.
    static func info(_ category: String, _ message: String) {
        let clean = LogRedactor.redact(message)
        logger(category).info("\(clean, privacy: .public)")
        DiagnosticsRingBuffer.shared.append(category: category, level: "info", message: clean)
    }

    /// Error that may name a type or code, but never a secret. The message is redacted
    /// before OSLog and before the ring buffer.
    static func error(_ category: String, _ message: String) {
        let clean = LogRedactor.redact(message)
        logger(category).error("\(clean, privacy: .public)")
        DiagnosticsRingBuffer.shared.append(category: category, level: "error", message: clean)
    }

    /// Private detail — visible in Console only when the device is unlocked with a debugger.
    /// Still redacted before it enters the feedback ring.
    static func debug(_ category: String, _ message: String) {
        let clean = LogRedactor.redact(message)
        logger(category).debug("\(clean, privacy: .private)")
        DiagnosticsRingBuffer.shared.append(category: category, level: "debug", message: clean)
    }

    /// Records a provider / model failure code without echoing payload text.
    static func providerError(backend: String, model: String?, code: String) {
        let line = "backend=\(backend) model=\(model ?? "-") code=\(code)"
        error("provider", line)
        ProviderDiagnostics.shared.record(backend: backend, model: model, errorCode: code)
    }
}

/// Last provider/model touch used in a feedback snapshot.
final class ProviderDiagnostics: @unchecked Sendable {
    static let shared = ProviderDiagnostics()

    private let lock = NSLock()
    private var backend: String = ""
    private var model: String?
    private var lastErrorCode: String?

    func record(backend: String, model: String?, errorCode: String?) {
        lock.lock()
        defer { lock.unlock() }
        self.backend = backend
        self.model = model
        if let errorCode { lastErrorCode = errorCode }
    }

    func snapshot() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        var out: [String: Any] = ["backend": backend]
        if let model { out["model"] = model }
        if let lastErrorCode { out["last_error"] = lastErrorCode }
        return out
    }
}
