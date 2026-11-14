// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Connecting through the Meta AI app: what to do there first, how one try is followed
// from the tap to its outcome, and what to say when it does not work.
//
// The Meta AI app can refuse a test build and say only "Internal error". The glasses
// toolkit then reports nothing to Phoenix Fox: no error is thrown and no link brings the
// wearer back. So a try is judged by what is true when the wearer returns, not only by
// an error. The rules are here, without the toolkit, so they can be tested.

import Foundation

/// The versions the glasses toolkit this app is built with needs.
enum GlassesRequirements {
    static let metaAIVersion = 292
    static let glassesVersion = 128
}

/// What to do in the Meta AI app before connecting. Shown before the button that opens it.
enum GlassesPreparation {
    static let heading = "First, in the Meta AI app"

    /// Where Developer Mode is, in the words on the screen.
    static let developerModePath = "open Settings, then App Info, and tap the version number five times"

    static let steps = [
        "Pair your glasses in the Meta AI app, and check that they show as connected there.",
        "Update Meta AI to version \(GlassesRequirements.metaAIVersion) or later, and your glasses to version \(GlassesRequirements.glassesVersion) or later.",
        "Turn on Developer Mode. In Meta AI, \(developerModePath). Switch Developer Mode on and leave it on.",
    ]

    /// Why Developer Mode is asked for.
    static let reason = "Phoenix Fox is a test build. Meta AI connects to a test build only while Developer Mode is on."
}

/// Where the glasses toolkit says the connection to Meta AI stands. The names are the
/// toolkit's own, so a line in the log can be compared with Meta's documentation.
enum RegistrationStage: String, Equatable, Sendable {
    /// The toolkit did not start in this build.
    case notRunning = "not running"
    case unavailable
    case available
    case registering
    case registered
}

/// Why a try at connecting ended without a connection.
enum RegistrationStall: Equatable, Sendable {
    /// Meta AI was asked to open and Phoenix Fox stayed on the screen.
    case didNotOpen
    /// The wearer went to Meta AI and came back, and the glasses are still not connected.
    case returnedUnconnected
    case notInstalled
    case offline
    /// The Meta values in this build are missing or wrong.
    case badBuild
    /// The toolkit did not start. The text says why.
    case notRunning(String)
    /// The toolkit refused and said why, in its own words.
    case refused(String)

    var title: String {
        switch self {
        case .didNotOpen: return "Meta AI did not open"
        case .returnedUnconnected, .refused: return "Meta AI did not connect your glasses"
        case .notInstalled: return "Meta AI is not installed"
        case .offline: return "No internet connection"
        case .badBuild, .notRunning: return "This build cannot connect to glasses"
        }
    }

    var explanation: String {
        switch self {
        case .didNotOpen:
            return "Phoenix Fox asked the Meta AI app to open and it did not."
        case .returnedUnconnected:
            return "If Meta AI showed “Internal error”, it refused this test build. The usual cause is Developer Mode being off. Try these in order."
        case .refused(let words):
            return "Meta AI answered: \(Self.sentence(words)) The usual cause is Developer Mode being off. Try these in order."
        case .notInstalled:
            return "Your glasses are set up in the Meta AI app, and Phoenix Fox connects through it."
        case .offline:
            return "Connecting your glasses needs the internet once."
        case .badBuild:
            return "This build is missing its Meta app settings. Nothing on this phone can fix that."
        case .notRunning(let why):
            return why
        }
    }

    /// What to do, in order. The last step is always the one that tries again.
    var steps: [String] {
        switch self {
        case .didNotOpen:
            return [
                "Check that the Meta AI app is installed and that you are signed in to it.",
                "Open Meta AI once and check that your glasses show as connected.",
                "Come back here and try again.",
            ]
        case .returnedUnconnected, .refused:
            return [
                "In Meta AI, turn Developer Mode off, then on again. To find it, \(GlassesPreparation.developerModePath).",
                "Update Meta AI to version \(GlassesRequirements.metaAIVersion) or later, and your glasses to version \(GlassesRequirements.glassesVersion) or later.",
                "Close Meta AI completely: swipe up from the bottom of the screen, then swipe Meta AI away.",
                "Come back here and try again.",
            ]
        case .notInstalled:
            return [
                "Install Meta AI from the App Store and sign in.",
                "Pair your glasses in Meta AI.",
                "Come back here and try again.",
            ]
        case .offline:
            return [
                "Check Wi-Fi or mobile data on this phone.",
                "Come back here and try again.",
            ]
        case .badBuild, .notRunning:
            return [
                "Install the newest Phoenix Fox build from TestFlight.",
                "Open it and connect your glasses again.",
            ]
        }
    }

    /// Trying again on this phone can help.
    var canRetry: Bool {
        switch self {
        case .badBuild, .notRunning: return false
        case .didNotOpen, .returnedUnconnected, .notInstalled, .offline, .refused: return true
        }
    }

    /// The toolkit's words as one sentence, so the next sentence does not run into them.
    private static func sentence(_ words: String) -> String {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return "No reason was given." }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }
}

/// A numbered list of things to do, and how VoiceOver reads each one.
enum NumberedStep {
    static func spoken(_ index: Int, of steps: [String]) -> String {
        "Step \(index + 1) of \(steps.count). \(steps[index])"
    }
}

/// One try at connecting, from the tap to the outcome.
struct RegistrationAttempt: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        /// The toolkit has been asked to open Meta AI.
        case opening
        /// Meta AI was opened. The wearer is there, or about to be.
        case away
        /// Back in Phoenix Fox, giving the answer a moment to arrive.
        case confirming
        case stalled(RegistrationStall)
    }

    /// A short wait the caller runs. It hands the same value back to `waited` when the
    /// time is up. Only the newest wait counts.
    struct Wait: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            /// For Meta AI to come to the front after it was asked to open.
            case forMetaAIToOpen
            /// For the connection to be confirmed after the wearer came back.
            case forAnswer
        }

        let kind: Kind
        let ticket: Int

        var seconds: Double {
            switch kind {
            case .forMetaAIToOpen: return 6
            case .forAnswer: return 4
            }
        }
    }

    private(set) var phase: Phase = .idle
    /// Phoenix Fox left the screen during this try, so Meta AI did open.
    private(set) var leftApp = false
    /// Meta AI sent the wearer back through its link during this try.
    private(set) var answerReceived = false
    private var answersRunning = 0
    private var ticket = 0

    /// The button that starts a try shows it is working.
    var isWorking: Bool {
        switch phase {
        case .opening, .away, .confirming: return true
        case .idle, .stalled: return false
        }
    }

    var stall: RegistrationStall? {
        if case .stalled(let stall) = phase { return stall }
        return nil
    }

    mutating func begin() {
        phase = .opening
        leftApp = false
        answerReceived = false
        ticket += 1
    }

    /// The toolkit returned without an error after being asked to open Meta AI.
    mutating func handedOff() -> Wait? {
        guard phase == .opening else { return nil }
        phase = .away
        return leftApp ? nil : issue(.forMetaAIToOpen)
    }

    /// The toolkit refused, or could not be asked.
    mutating func failed(_ stall: RegistrationStall) {
        phase = .stalled(stall)
        ticket += 1
    }

    mutating func enteredBackground() {
        if isWorking { leftApp = true }
    }

    mutating func becameActive() -> Wait? {
        guard isWorking, leftApp else { return nil }
        phase = .confirming
        return issue(.forAnswer)
    }

    /// Meta AI's link arrived and is being handled.
    mutating func answerBegan() {
        answersRunning += 1
    }

    /// The link was handled. `failure` is the toolkit's words when it reported an error.
    mutating func answerEnded(failure: String?) -> Wait? {
        answersRunning = max(0, answersRunning - 1)
        guard isWorking else { return nil }
        answerReceived = true
        leftApp = true
        if let failure {
            failed(.refused(failure))
            return nil
        }
        phase = .confirming
        return issue(.forAnswer)
    }

    mutating func waited(_ wait: Wait) {
        guard wait.ticket == ticket else { return }
        switch wait.kind {
        case .forMetaAIToOpen:
            if phase == .away, !leftApp { failed(.didNotOpen) }
        case .forAnswer:
            // While a link is still being handled, its end starts the next wait.
            if phase == .confirming, answersRunning == 0 { failed(.returnedUnconnected) }
        }
    }

    /// The toolkit reports the glasses connected. Any trouble shown is out of date.
    mutating func registered() {
        phase = .idle
        ticket += 1
    }

    /// The wearer put the trouble away, or disconnected.
    mutating func dismiss() {
        phase = .idle
        ticket += 1
    }

    /// One line for the log and for whoever is helping. It holds no names, IDs or keys.
    func details(stage: RegistrationStage) -> String {
        "Glasses toolkit: \(stage.rawValue). Meta AI opened: \(leftApp ? "yes" : "no"). Answer from Meta AI: \(answerReceived ? "yes" : "no")."
    }

    private mutating func issue(_ kind: Wait.Kind) -> Wait {
        ticket += 1
        return Wait(kind: kind, ticket: ticket)
    }
}
