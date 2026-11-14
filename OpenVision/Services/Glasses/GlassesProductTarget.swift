// Jarvis - GlassesProductTarget.swift
// v1 is the pair the owner wears today: Meta Glasses Adventurer.
//
// That is Meta's own-brand frame (not Ray-Ban, not Oakley, not Ray-Ban Display).
// The Wearables DAT SDK reports it as DeviceType.metaGlasses: a displayless
// Meta-branded glasses device. Camera, microphone, and open-ear speaker are the
// v1 path. In-lens HUD and Neural Band stay behind capability detection.

import Foundation
import MWDATCore

enum GlassesProductTarget {
    /// DAT enum for Meta's own-brand displayless frames, including Adventurer.
    static let v1DeviceType: DeviceType = .metaGlasses

    static func isV1Target(_ type: DeviceType) -> Bool {
        type == .metaGlasses
    }

    static func label(_ type: DeviceType) -> String {
        switch type {
        case .metaGlasses: return "Meta Glasses Adventurer"
        case .rayBanMeta: return "Ray-Ban Meta"
        case .rayBanMetaOptics: return "Ray-Ban Meta Optics"
        case .oakleyMetaHSTN: return "Oakley Meta HSTN"
        case .oakleyMetaVanguard: return "Oakley Meta Vanguard"
        case .metaRayBanDisplay: return "Meta Ray-Ban Display"
        case .unknown: return "Unrecognized glasses"
        @unknown default: return type.rawValue
        }
    }

    /// Display and Neural Band are detected, never required. Adventurer fails this check
    /// and the app stays on speaker and camera.
    static func needsDisplay(_ type: DeviceType) -> Bool {
        type.supportsDisplay
    }
}
