// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation
import Combine

/// Publishes the team board to the home screen. The relay client reports to it.
///
/// The board lives in memory. It starts empty with the app, because what an assistant was
/// doing before the app was closed is no longer something the app knows.
@MainActor
final class TeamBoardStore: ObservableObject {
    static let shared = TeamBoardStore()

    @Published private(set) var board: TeamBoard
    /// Counts replies and alerts, so the home screen can mark each new one with a haptic.
    @Published private(set) var arrivals = 0
    /// The newest arrival was an urgent alert.
    private(set) var lastArrivalUrgent = false

    private let now: () -> Date

    init(roster: [AssistantBot] = [], now: @escaping () -> Date = { Date() }) {
        board = TeamBoard(roster: roster)
        self.now = now
    }

    func sync(roster: [AssistantBot]) {
        var next = board
        next.sync(roster: roster)
        if next != board { board = next }
    }

    func asked(_ target: String?, task: String) {
        board.asked(target, task: task, at: now())
    }

    func answered(by name: String, text: String) {
        let before = board
        board.answered(by: name, text: text, at: now())
        if board != before {
            lastArrivalUrgent = false
            arrivals += 1
        }
    }

    func settled(_ target: String?) {
        board.settled(target, at: now())
    }

    func failed(_ target: String?, reason: String) {
        board.failed(target, reason: reason, at: now())
    }

    func alerted(by name: String, text: String, urgent: Bool) {
        let before = board
        board.alerted(by: name, text: text, urgent: urgent, at: now())
        if board != before {
            lastArrivalUrgent = urgent
            arrivals += 1
        }
    }
}
