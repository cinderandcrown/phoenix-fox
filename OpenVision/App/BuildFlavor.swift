// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// One flag decides whether this is the owner's build.
//
// The owner's TestFlight build turns every feature on and may use the glasses toolkit's
// beta capabilities, which Meta allows only in its development and beta release channels.
// Any other build starts with the cautious defaults and leaves the beta capabilities off,
// whatever its saved settings say.
//
// The flag is the build setting PHOENIX_FOX_OWNER_BUILD, which reaches the app through
// Info.plist. It is NO in the project and YES in the TestFlight workflow. It is read at
// run time and not with `#if`, so both kinds of build compile the same code and CI checks
// all of it.

import Foundation

enum BuildFlavor: Equatable, Sendable {
    case owner
    case standard

    static let infoKey = "PhoenixFoxOwnerBuild"

    /// The flavor of the running app.
    static let current = BuildFlavor(infoValue: Bundle.main.object(forInfoDictionaryKey: infoKey))

    /// Reads the Info.plist value. A build setting that was never set arrives as an empty
    /// string, or as the unexpanded `$(…)` text, and both mean a standard build.
    init(infoValue: Any?) {
        switch infoValue {
        case let flag as Bool:
            self = flag ? .owner : .standard
        case let text as String:
            let word = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self = ["yes", "true", "1"].contains(word) ? .owner : .standard
        default:
            self = .standard
        }
    }

    /// Whether toolkit capabilities Meta still calls beta may run.
    var allowsExperimental: Bool { self == .owner }

    var label: String {
        switch self {
        case .owner: return "Owner build"
        case .standard: return "Standard build"
        }
    }
}
