// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Whether the phone can reach the internet. Drives the Offline mode indicator and the
// on-device-first gate for cloud brains. Uses Network.framework only.

import Foundation
import Network

@MainActor
final class NetworkPath: ObservableObject {
    static let shared = NetworkPath()

    @Published private(set) var status: NetworkPathStatus = .online

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "llc.cinderandcrown.phoenixfox.network")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let next: NetworkPathStatus = path.status == .satisfied ? .online : .offline
            Task { @MainActor in
                guard let self, self.status != next else { return }
                self.status = next
                print("[NetworkPath] \(next.title)")
            }
        }
        monitor.start(queue: queue)
    }
}
