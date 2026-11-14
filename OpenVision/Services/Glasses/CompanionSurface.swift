// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation

/// The one way a reply reaches the wearer.
///
/// The line is always spoken. That is the whole output on glasses with no display, and it
/// is what remains if a display send fails. A card is drawn on the lens as well, but only
/// when the paired glasses report a display. Callers never branch on the hardware, so a
/// new kind of output is added here and not at each call site.
///
/// Cards go through `CompanionCard` so a future Ray-Ban Display Web App can render the
/// same payload (see docs/DISPLAY_WEB_APP_PLAN.md).
@MainActor
enum CompanionSurface {
    /// - Parameters:
    ///   - bot: Who is answering. Nil or empty shows "Phoenix Fox" on the card.
    ///   - text: The reply as written. This is what a card shows.
    ///   - speak: Says the line. It gets the trimmed text, and may say a longer form of it,
    ///     such as the text with the assistant's name in front.
    static func present(bot: String?, text: String, kind: HudCard.Kind = .reply, speak: (String) -> Void) {
        let name = bot.flatMap { $0.isEmpty ? nil : $0 } ?? "Phoenix Fox"
        let cardKind: CompanionCard.Kind
        var bullets: [String] = []
        switch kind {
        case .reply: cardKind = .reply
        case .alert: cardKind = .alert
        case .briefing:
            cardKind = .briefing
            bullets = text
                .replacingOccurrences(of: "\n", with: ". ")
                .split(separator: ".")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count > 2 }
            bullets = Array(bullets.prefix(5))
        }
        let card = CompanionCard(
            kind: cardKind,
            bot: name,
            text: bullets.first ?? text,
            bullets: bullets,
            actions: ["next", "dismiss", "talk"]
        )
        CompanionCardPresenter.present(card, speak: speak)
    }

    /// Presents an already-built portable card (inbox item, resume prompt, …).
    static func present(_ card: CompanionCard, speak: (String) -> Void) {
        CompanionCardPresenter.present(card, speak: speak)
    }
}
