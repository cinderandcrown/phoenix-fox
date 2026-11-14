// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Jarvis - GlassesHUD.swift
// In-lens cards for Meta Ray-Ban Display. Audio-only glasses never touch this path.
//
// Official API (DAT 1.0.1, MWDATDisplay): DeviceSession.addDisplay(), Display.send(_:),
// Display.clearDisplay(). Cards are FlexBox / Text / Icon trees, not pixels.
// Neural Band gestures are interpreted by GestureMap and move this queue.

import Foundation
import MWDATCore
import MWDATDisplay

struct HudCard: Identifiable, Equatable {
    enum Kind: Equatable { case reply, alert, briefing }
    let id: UUID
    var bot: String
    var text: String
    var kind: Kind
    var bullets: [String]

    init(bot: String, text: String, kind: Kind, bullets: [String] = []) {
        id = UUID()
        self.bot = bot
        self.text = text
        self.kind = kind
        self.bullets = bullets
    }
}

@MainActor
final class GlassesHUD {
    static let shared = GlassesHUD()

    private(set) var displayAvailable = false
    private(set) var bandDetected = false
    private var display: Display?
    private var cards: [HudCard] = []
    private var index = 0
    private var onTalk: (() -> Void)?

    private init() {}

    func setTalkHandler(_ handler: @escaping () -> Void) {
        onTalk = handler
    }

    /// Call once a device session is `.started`. Throws are swallowed: no display means audio only.
    func attach(to session: DeviceSession, device: Device?) {
        let type = device?.deviceType()
        let typeSupports = type?.supportsDisplay == true || device?.supportsDisplay() == true
        guard typeSupports else {
            displayAvailable = false
            display = nil
            if let type, GlassesProductTarget.isV1Target(type) {
                GlassesLink.shared.record("Adventurer has no display. Replies stay on the speaker.")
            }
            return
        }
        do {
            let display = try session.addDisplay()
            display.start()
            self.display = display
            displayAvailable = true
            GlassesLink.shared.record("Display attached (\(device?.deviceType().rawValue ?? "unknown"))")
        } catch {
            displayAvailable = false
            display = nil
            GlassesLink.shared.record("Display unavailable, audio only: \(error.localizedDescription)")
        }
    }

    func detach() {
        display?.stop()
        display = nil
        displayAvailable = false
        cards.removeAll()
        index = 0
    }

    func present(_ card: HudCard) {
        cards.append(card)
        index = cards.count - 1
        Task { await renderCurrent() }
    }

    func presentReply(bot: String, text: String) {
        present(HudCard(bot: bot, text: Self.clip(text, 180), kind: .reply))
    }

    func presentAlert(bot: String, text: String) {
        present(HudCard(bot: bot, text: Self.clip(text, 140), kind: .alert))
    }

    func presentBriefing(bot: String, text: String) {
        let bullets = Self.bullets(from: text)
        present(HudCard(bot: bot, text: bullets.first ?? Self.clip(text, 120), kind: .briefing, bullets: bullets))
    }

    func handle(_ signal: GestureSignal) {
        let (gesture, sawBand) = GestureMap.interpret(signal)
        if sawBand { bandDetected = true }
        switch gesture {
        case .next:
            guard !cards.isEmpty else { return }
            index = min(index + 1, cards.count - 1)
            Task { await renderCurrent() }
        case .dismiss:
            guard !cards.isEmpty else {
                Task { await clear() }
                return
            }
            cards.remove(at: index)
            index = min(index, max(cards.count - 1, 0))
            Task { await renderCurrent() }
        case .talkOrConfirm:
            onTalk?()
        case .look, .note, nil:
            break
        }
    }

    private func renderCurrent() async {
        guard displayAvailable, let display else { return }
        guard cards.indices.contains(index) else {
            await clear()
            return
        }
        let card = cards[index]
        let icon: IconName = card.kind == .alert ? .bell : (card.kind == .briefing ? .threeHorizontalLines : .speechBubble)
        var lines: [Text] = [
            Text(card.bot, style: .meta, color: .secondary),
            Text(card.text, style: .body),
        ]
        if card.kind == .briefing {
            lines += card.bullets.prefix(4).map { Text("• \(Self.clip($0, 80))", style: .body, color: .secondary) }
        }
        let position = cards.count > 1 ? "\(index + 1)/\(cards.count)" : ""
        let view = FlexBox(direction: .column, spacing: 6, alignment: .start, crossAlignment: .start) {
            Icon(name: icon, style: .outline)
            Text(card.kind == .alert ? "Alert" : "Phoenix Fox", style: .heading)
            lines[0]
            lines[1]
        }
        .padding(10)
        .background(.card)
        do {
            try await display.send(view)
            if card.kind == .briefing, lines.count > 2 {
                // A second send replaces the card with the bullet list. One card, not a stack of frames.
                let detailed = FlexBox(direction: .column, spacing: 4) {
                    Text(card.bot, style: .heading)
                    for line in lines.dropFirst().prefix(5) { line }
                    if !position.isEmpty { Text(position, style: .meta, color: .secondary) }
                }
                .padding(10)
                .background(.card)
                try await display.send(detailed)
            }
        } catch {
            displayAvailable = false
            GlassesLink.shared.record("HUD send failed, staying on audio: \(error.localizedDescription)")
        }
    }

    private func clear() async {
        guard let display else { return }
        try? await display.clearDisplay()
    }

    private static func clip(_ text: String, _ max: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max - 1)) + "…"
    }

    private static func bullets(from text: String) -> [String] {
        let parts = text
            .replacingOccurrences(of: "\n", with: ". ")
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 2 }
        return Array(parts.prefix(5))
    }
}

/// One output path for a reply.
///
/// Speech always happens. That is the Adventurer path, and it is also the fallback when a
/// display send fails. A lens card is added only when the paired glasses report a display,
/// so Meta Ray-Ban Display uses this same call. Callers do not branch on hardware.
@MainActor
enum CompanionSurface {
    static func present(
        bot: String?,
        text: String,
        kind: HudCard.Kind = .reply,
        speak: (String) -> Void
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        speak(trimmed)
        guard GlassesLink.shared.displayCapable else { return }
        let name = (bot?.isEmpty == false ? bot : nil) ?? "Phoenix Fox"
        switch kind {
        case .reply:
            GlassesHUD.shared.presentReply(bot: name, text: trimmed)
        case .alert:
            GlassesHUD.shared.presentAlert(bot: name, text: trimmed)
        case .briefing:
            GlassesHUD.shared.presentBriefing(bot: name, text: trimmed)
        }
    }
}
