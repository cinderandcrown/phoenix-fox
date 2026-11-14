// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation

/// The one way a reply reaches the wearer.
///
/// The line is always spoken. That is the whole output on glasses with no display, and it
/// is what remains if a display send fails. A card is drawn on the lens as well, but only
/// when the paired glasses report a display. Callers never branch on the hardware, so a
/// new kind of output is added here and not at each call site.
@MainActor
enum CompanionSurface {
    /// - Parameters:
    ///   - bot: Who is answering. Nil or empty shows "Phoenix Fox" on the card.
    ///   - text: The reply as written. This is what a card shows.
    ///   - speak: Says the line. It gets the trimmed text, and may say a longer form of it,
    ///     such as the text with the assistant's name in front.
    static func present(bot: String?, text: String, kind: HudCard.Kind = .reply, speak: (String) -> Void) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        speak(line)
        guard GlassesLink.shared.displayCapable else { return }
        let name = bot.flatMap { $0.isEmpty ? nil : $0 } ?? "Phoenix Fox"
        switch kind {
        case .reply: GlassesHUD.shared.presentReply(bot: name, text: line)
        case .alert: GlassesHUD.shared.presentAlert(bot: name, text: line)
        case .briefing: GlassesHUD.shared.presentBriefing(bot: name, text: line)
        }
    }
}
