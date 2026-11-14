// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Head yes / skip for "Walk my inbox" and other list walk-throughs.
//
// Nod (HeadAnswer.yes) → act on the current item.
// Shake (HeadAnswer.no) → skip to the next.
// Spoken yes/no still work through the same HeadAnswerPolicy.yesOrNo path.

import Foundation

enum InboxWalkAction: Equatable, Sendable {
    case act
    case skip
}

/// One item in a walk-through list. The feature that owns the list supplies these.
struct InboxWalkItem: Equatable, Sendable, Identifiable {
    var id: String
    var spokenSummary: String
}

/// Pure controller: feeds items, maps head answers to act/skip, advances the cursor.
struct InboxWalkController: Sendable {
    private(set) var items: [InboxWalkItem]
    private(set) var index: Int
    /// While true, a nod/shake is claimed by this walk and must not quiet Jarvis.
    var isActive: Bool { !items.isEmpty && index < items.count }

    var headAnswerPolicy: HeadAnswerPolicy {
        isActive ? .yesOrNo : .none
    }

    var current: InboxWalkItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    init(items: [InboxWalkItem] = []) {
        self.items = items
        self.index = 0
    }

    mutating func start(_ items: [InboxWalkItem]) {
        self.items = items
        self.index = 0
    }

    mutating func stop() {
        items = []
        index = 0
    }

    /// Maps a head answer onto the current item. Returns nil when the walk is idle.
    mutating func take(_ answer: HeadAnswer) -> (item: InboxWalkItem, action: InboxWalkAction)? {
        guard let item = current else { return nil }
        let action: InboxWalkAction = answer == .yes ? .act : .skip
        index += 1
        if index >= items.count {
            items = []
            index = 0
        }
        return (item, action)
    }
}
