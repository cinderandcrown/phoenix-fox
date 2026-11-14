// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation

/// Resumes a checked continuation at most once.
///
/// For a callback API raced against a timeout or a cancel: whichever side arrives first wins
/// and the others become no-ops, so the continuation is never resumed twice and never leaked.
final class ResumeOnce<Value: Sendable, Failure: Error>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Failure>?

    init(_ continuation: CheckedContinuation<Value, Failure>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Value, Failure>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    func resume(returning value: Value) {
        resume(with: .success(value))
    }

    func resume(throwing error: Failure) {
        resume(with: .failure(error))
    }
}
