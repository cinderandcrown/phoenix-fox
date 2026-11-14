// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Jarvis - GestureMap.swift
// Vendor-neutral reading of glasses and Neural Band input.
//
// The Wearables DAT SDK does not give third-party apps raw EMG samples. A Neural Band
// arrives as semantic InputEvents (select, nav, drag) tagged with source `.neuralBand`
// or `.neuralBandDrag`. Temple-pad touches use `.captouch`. This map is the one place
// that turns those signals into talk / next / dismiss, so a future pinch-specific event
// is a new case here rather than a new call site.

import Foundation

enum GlassesGesture: Equatable {
    /// Pinch or tap: start talking, or confirm the card in front of the wearer.
    case talkOrConfirm
    /// Swipe onward through HUD cards.
    case next
    /// Swipe away the current card.
    case dismiss
    /// Capture button: look with the camera.
    case look
    /// Long capture press: start a note.
    case note
}

struct GestureSignal: Equatable {
    enum Source: Equatable {
        case temple
        case band
        case bandDrag
        case captureButton
        case actionButton
        case unknown
    }
    enum Nav: Equatable { case up, down, left, right }
    enum Press: Equatable { case short, hold, double }
    enum Kind: Equatable {
        case select
        case nav(Nav)
        case back
        case capture(Press)
        case dragEnded(dx: Float)
        case action
    }
    var source: Source
    var kind: Kind
}

enum GestureMap {
    /// Returns the product gesture and whether this signal is evidence a Neural Band is paired.
    static func interpret(_ signal: GestureSignal) -> (gesture: GlassesGesture?, sawBand: Bool) {
        let sawBand = signal.source == .band || signal.source == .bandDrag
        switch signal.kind {
        case .select:
            return (.talkOrConfirm, sawBand)
        case .action:
            return (.talkOrConfirm, sawBand)
        case .back:
            return (.dismiss, sawBand)
        case .nav(let direction):
            switch direction {
            case .right, .down: return (.next, sawBand)
            case .left, .up: return (.dismiss, sawBand)
            }
        case .capture(let press):
            switch press {
            case .short, .double: return (.look, sawBand)
            case .hold: return (.note, sawBand)
            }
        case .dragEnded(let dx):
            if dx > 12 { return (.next, sawBand) }
            if dx < -12 { return (.dismiss, sawBand) }
            return (nil, sawBand)
        }
    }
}
