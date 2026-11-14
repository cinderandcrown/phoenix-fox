// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Remembers recent AVAudioSession route changes for beta diagnostics.
// Descriptions name ports only — never audio buffers.

import AVFoundation
import Foundation

final class AudioRouteHistory: @unchecked Sendable {
    static let shared = AudioRouteHistory()

    struct Entry: Sendable, Equatable {
        var at: Date
        var description: String
        var reason: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let capacity = 20
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        record(reason: "start")
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let reasonCode = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            self?.record(reason: Self.label(reasonCode))
        }
    }

    func record(reason: String) {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.currentRoute.inputs.map(\.portName).joined(separator: ", ")
        let outputs = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
        let description = "in=[\(inputs)] out=[\(outputs)]"
        let entry = Entry(at: Date(), description: description, reason: reason)
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        FoxLog.info("audio", "route \(reason): \(description)")
    }

    func snapshot() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        let formatter = ISO8601DateFormatter()
        return entries.map { entry in
            [
                "at": formatter.string(from: entry.at),
                "route": entry.description,
                "reason": entry.reason,
            ]
        }
    }

    private static func label(_ reason: AVAudioSession.RouteChangeReason?) -> String {
        switch reason {
        case .newDeviceAvailable: return "newDevice"
        case .oldDeviceUnavailable: return "oldDeviceGone"
        case .categoryChange: return "category"
        case .override: return "override"
        case .wakeFromSleep: return "wake"
        case .noSuitableRouteForCategory: return "noSuitableRoute"
        case .routeConfigurationChange: return "config"
        default: return "unknown"
        }
    }
}
