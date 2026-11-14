// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Display-agnostic companion cards.
//
// The same payload can render on:
//   1. Spoken audio only (Adventurer / displayless) via CompanionSurface
//   2. DAT MWDATDisplay FlexBox cards (Meta Ray-Ban Display) via GlassesHUD
//   3. A future Meta Ray-Ban Display Web App (HTML/CSS/JS + Neural Band + WebMCP)
//
// Keep this type free of UIKit / SwiftUI / MWDATDisplay so a Web App (or JSON bridge)
// can consume an identical schema. See docs/DISPLAY_WEB_APP_PLAN.md.

import Foundation

/// Portable card the companion shows the wearer.
struct CompanionCard: Equatable, Sendable, Identifiable, Codable {
    enum Kind: String, Equatable, Sendable, Codable {
        case reply
        case alert
        case briefing
        case caption
        case resume
        case inboxItem
    }

    var id: String
    var kind: Kind
    /// Who is speaking / responsible. Empty means Phoenix Fox.
    var bot: String
    /// Primary line (spoken and shown).
    var text: String
    /// Optional secondary lines (briefing bullets, inbox meta).
    var bullets: [String]
    /// Optional action hints for Neural Band / WebMCP (act, skip, dismiss, talk).
    var actions: [String]

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        bot: String = "Phoenix Fox",
        text: String,
        bullets: [String] = [],
        actions: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.bot = bot
        self.text = text
        self.bullets = bullets
        self.actions = actions
    }

    /// Maps into the existing HUD card shape without losing portability.
    func asHudCard() -> HudCard {
        let hudKind: HudCard.Kind
        switch kind {
        case .alert: hudKind = .alert
        case .briefing, .inboxItem, .resume: hudKind = .briefing
        case .reply, .caption: hudKind = .reply
        }
        return HudCard(bot: bot, text: text, kind: hudKind, bullets: bullets)
    }

    static func from(hud card: HudCard) -> CompanionCard {
        let kind: Kind
        switch card.kind {
        case .alert: kind = .alert
        case .briefing: kind = .briefing
        case .reply: kind = .reply
        }
        return CompanionCard(
            id: card.id.uuidString,
            kind: kind,
            bot: card.bot,
            text: card.text,
            bullets: card.bullets,
            actions: ["next", "dismiss", "talk"]
        )
    }
}

/// Renders a portable card on every surface that currently exists.
@MainActor
enum CompanionCardPresenter {
    static func present(_ card: CompanionCard, speak: (String) -> Void) {
        let line = card.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        speak(line)
        guard GlassesLink.shared.displayCapable else { return }
        GlassesHUD.shared.present(card.asHudCard())
    }
}
