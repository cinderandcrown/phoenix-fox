// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import UIKit

extension HapticCue {
    /// Plays the cue with the system's own feedback, so it follows the phone's haptic
    /// settings and feels like the rest of iOS.
    @MainActor
    func play() {
        switch self {
        case .listening:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heard:
            UISelectionFeedbackGenerator().selectionChanged()
        case .replying:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .cameraOn:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .arrived:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .urgent:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .trouble:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
