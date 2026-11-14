// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation

/// Everything the home screen shows, as plain values.
///
/// `VoiceAgentView` fills this in from the running app. Previews and snapshot tests fill
/// it in by hand, so the screen can be drawn in any state without glasses, a relay, or a
/// microphone.
struct HomeModel: Equatable, Sendable {
    /// What the "Your team" part of the screen is.
    enum Team: Equatable, Sendable {
        /// The relay is set up: a card for each assistant.
        case members([TeamBoard.Member])
        /// My assistants is chosen and the relay is not set up yet.
        case connect
        /// Another AI is chosen. Its name is shown.
        case brain(String)
    }

    var signals = LiveSignals()
    var glasses = GlassesStatus.notConnected
    var team = Team.connect
    var now = Date()

    /// The last thing the wearer said, and the last answer.
    var heard = ""
    var reply = ""
    var showsExchange = true

    /// The companion's status line and live caption.
    var status = ""
    var caption = ""
    /// Live captions are read at arm's length, so they are set larger.
    var largeCaption = false

    /// The document that answers are being drawn from, when one is open.
    var document: String?

    var canRecord = false
    var isRecording = false
    var recordingNote: String?

    var trouble: String?

    /// Holds the orb's clock still. For previews and snapshot tests.
    var fixedTime: Double?

    var phase: LivePhase { LivePhase(signals) }
}

/// What the home screen can ask the app to do.
struct HomeActions {
    var stage: (StageTap) -> Void = { _ in }
    var glasses: () -> Void = {}
    var record: () -> Void = {}
    var closeDocument: () -> Void = {}
    var dismissTrouble: () -> Void = {}
    var connectAssistants: () -> Void = {}
    var chooseBrain: () -> Void = {}
}

#if DEBUG
/// Made-up states of the home screen for previews and snapshot tests. Debug builds only,
/// so none of it ships.
enum HomeSamples {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static let team: [TeamBoard.Member] = {
        var board = TeamBoard(roster: AssistantRoster.seed)
        board.answered(by: "Fire Fox", text: "Three things today. The supplier call is at two.", at: now.addingTimeInterval(-900))
        board.asked("Indy", task: "check the supplier invoice against the order", at: now.addingTimeInterval(-20))
        board.alerted(by: "Driver", text: "The build finished. All tests passed.", urgent: false, at: now.addingTimeInterval(-3700))
        board.asked("Rally", task: "status", at: now.addingTimeInterval(-600))
        board.failed("Rally", reason: "The relay did not answer in time.", at: now.addingTimeInterval(-420))
        return board.members
    }()

    /// First launch: nothing connected.
    static var fresh: HomeModel {
        HomeModel(now: now, fixedTime: 0)
    }

    /// Waiting for the wake word, with the team idle.
    static var ready: HomeModel {
        HomeModel(
            glasses: .ready,
            team: .members(TeamBoard(roster: AssistantRoster.seed).members),
            now: now,
            fixedTime: 0
        )
    }

    static var listening: HomeModel {
        var model = ready
        model.signals.activity = .listening
        return model
    }

    /// Looking through the camera at something the wearer asked about.
    static var seeing: HomeModel {
        var model = ready
        model.signals.activity = .thinking
        model.signals.cameraOn = true
        model.glasses = .cameraOn
        model.heard = "What does this label say?"
        return model
    }

    /// Indy has the question.
    static var asking: HomeModel {
        var model = ready
        model.signals.activity = .thinking
        model.signals.askedAssistant = "Indy"
        model.team = .members(team)
        model.heard = "Ask Indy to check the supplier invoice against the order."
        return model
    }

    static var replying: HomeModel {
        var model = asking
        model.signals.activity = .speaking
        model.signals.askedAssistant = nil
        model.reply = "The invoice matches the order. Two filters are back-ordered until Friday."
        return model
    }

    /// Another AI is chosen, and something has gone wrong.
    static var trouble: HomeModel {
        HomeModel(
            glasses: .away,
            team: .brain("On this phone"),
            now: now,
            trouble: "No connection. Jarvis will answer on this phone until it is back.",
            fixedTime: 0
        )
    }

    /// Every state above, by name, in the order the design document shows them.
    static let all: [(name: String, model: HomeModel)] = [
        ("fresh", fresh),
        ("ready", ready),
        ("listening", listening),
        ("seeing", seeing),
        ("asking", asking),
        ("replying", replying),
        ("trouble", trouble),
    ]
}
#endif
