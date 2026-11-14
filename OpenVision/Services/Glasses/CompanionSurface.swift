// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// One reply, two outputs. Adventurer always hears the line. A lens card is
// drawn only after the glasses report a display and the HUD session is up.
// A future Display pair uses the same call. Adventurer never enters it.

import Foundation

@MainActor
enum CompanionSurface {
    static func showOnLens(text: String, bot: String?) {
        guard GlassesLink.shared.displayCapable else { return }
        GlassesHUD.shared.presentReply(bot: bot ?? "Phoenix Fox", text: text)
    }
}
