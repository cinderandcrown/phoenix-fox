// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Look to Talk, joined to the camera, the speaker, and the voice turn.
//
// The rules are in `Core`: what a frame shows, when a run of looks is a choice, what is
// said. This file does only what those cannot: it turns the glasses camera on and off,
// has the phone read each frame, plays the tones, and tells the voice turn who is held.
//
// The camera is on only while Look to Talk is looking, and the capture light is on with
// it. Frames are read on the phone and dropped. None is stored and none is sent.

import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class LookToTalk: ObservableObject {
    static let shared = LookToTalk()

    /// What a spoken sentence came to.
    enum Reply: Equatable {
        /// Say this. The sentence was a Look to Talk command.
        case say(String)
        /// Run this request as a turn. It goes to the assistant that one look found, and
        /// `naming` is said first when the wearer has not yet heard who that is.
        case send(String, naming: String?)
    }

    /// For the home screen.
    @Published private(set) var status = LookStatus.off

    /// Opens the microphone for one sentence, as the wake word would. Set by the voice screen.
    var listen: (() -> Void)?
    /// True while live video or a recording has the camera. Set by the voice screen.
    var cameraBusyElsewhere: () -> Bool = { false }

    private var tracker = LookTracker()
    private var loop: Task<Void, Never>?
    /// This turned the camera on, so this turns it off.
    private var startedCamera = false

    /// A request waiting on "Send that to Indy?".
    private struct Held {
        var request: String
        var target: LookTarget
        var asked: Date
    }

    private var waiting: Held?
    /// Who the one request now being sent goes to.
    private var once: String?

    private static let waitingPatience: TimeInterval = 12

    private init() {}

    private var workshop: WorkshopSettings { SettingsManager.shared.workshop }
    private var bots: [AssistantBot] { AssistantRoster.normalized(SettingsManager.shared.settings.assistantBots) }

    // MARK: - For the voice turn

    /// The assistant requests go to when no name is said. Nil when nothing is held, and
    /// always nil with the switch off.
    var focus: String? {
        guard workshop.lookToTalk else { return nil }
        return once ?? tracker.held?.name
    }

    /// A request went to an assistant. One sent to the held assistant keeps its lock alive.
    func sent(to name: String) {
        guard name == tracker.held?.name else { return }
        tracker.used(at: Date())
    }

    /// The one request has been sent, or was answered on the phone.
    func endOnce() {
        once = nil
    }

    /// Which answers a nod or a shake of the head may give right now.
    ///
    /// A nod may choose who is listened to, because that sends nothing. A request that
    /// is waiting to be sent needs its yes spoken.
    var headAnswerPolicy: HeadAnswerPolicy {
        guard workshop.lookToTalk else { return .none }
        if let waiting, Date().timeIntervalSince(waiting.asked) < Self.waitingPatience { return .noOnly }
        return tracker.question == nil ? .none : .yesOrNo
    }

    /// Offers a sentence to Look to Talk. Nil when it is not one of its commands.
    func handle(_ text: String) async -> Reply? {
        let settings = workshop
        guard settings.lookToTalk else {
            // Switched off while something was held.
            if !tracker.isOff { stop() }
            return nil
        }
        let now = Date()
        let names = bots.map(\.name)
        let held = waiting.flatMap { now.timeIntervalSince($0.asked) < Self.waitingPatience ? $0 : nil }
        waiting = nil
        let context = LookCommand.Context(
            enabled: true,
            bots: names,
            active: !tracker.isOff,
            asking: held != nil || tracker.question != nil
        )
        guard let command = LookCommand.parse(text, context: context) else { return nil }
        tracker.rules = settings.lookRules

        if let held {
            switch command {
            case .yes:
                once = held.target.name
                return .send(held.request, naming: nil)
            case .lock(let name?):
                once = name
                return .send(held.request, naming: name)
            case .no:
                return .say("OK. I haven't sent it.")
            default:
                break
            }
        }

        switch command {
        case .start, .again:
            if let trouble = troubleStarting() { return .say(trouble) }
            return .say(apply(tracker.start(at: now)))
        case .stop, .unlock:
            let line = apply(tracker.release())
            await releaseCamera()
            return .say(line)
        case .lock(let name):
            if name != nil, !SettingsManager.shared.settings.isOwnAssistantConfigured {
                return .say("Connect your assistants first, in Settings.")
            }
            let line = apply(tracker.lock(name.map(LookTarget.assistant), at: now))
            await releaseCamera()
            return .say(line)
        case .who:
            return .say(tracker.status.spoken(usual: AssistantRoster.defaultBot(in: bots).name))
        case .yes:
            return .say(apply(tracker.answer(true, at: now)))
        case .no:
            return .say(apply(tracker.answer(false, at: now)))
        case .once(let request):
            return await lookOnce(for: request)
        }
    }

    /// Everything off: nothing held, and the camera off if this turned it on.
    func stop() {
        _ = apply(tracker.release(), tones: false)
        waiting = nil
        once = nil
        Task { await releaseCamera() }
    }

    private func troubleStarting() -> String? {
        guard SettingsManager.shared.settings.isOwnAssistantConfigured else {
            return "Connect your assistants first, in Settings."
        }
        guard GlassesManager.shared.isRegistered else {
            return "The glasses aren't connected. Say lock on to, and a name, to choose an assistant without them."
        }
        return nil
    }

    // MARK: - One look for one request

    private func lookOnce(for request: String) async -> Reply {
        // What is already held is what "this one" means.
        if let held = tracker.held {
            once = held.name
            return .send(request, naming: nil)
        }
        if let trouble = troubleStarting() { return .say(trouble) }

        let glasses = GlassesManager.shared
        let wasStreaming = glasses.isStreaming
        if !wasStreaming { await glasses.startStreaming(for: .lookToTalk) }
        let began = Date()
        var look = LookOnce()
        var outcome = LookOnce.Outcome.nothing
        var read = Date.distantPast
        // A few frames, about half a second apart, and no longer than six seconds in all.
        while Date().timeIntervalSince(began) < 6 {
            try? await Task.sleep(for: .milliseconds(450))
            guard glasses.lastFrameTime > read, glasses.lastFrameTime > began, let image = glasses.lastFrame else { continue }
            read = glasses.lastFrameTime
            if let settled = look.looked(await reading(of: image)) {
                outcome = settled
                break
            }
        }
        if !wasStreaming, !cameraWantedElsewhere { await glasses.stopStreaming() }

        switch outcome {
        case .send(let target):
            play(.found, target)
            once = target.name
            return .send(request, naming: target.name)
        case .ask(let target):
            play(.unsure, target)
            waiting = Held(request: request, target: target, asked: Date())
            return .say("Send that to \(target.name)? Say yes or no.")
        case .nothing:
            return .say("I can't see an assistant's window. Say the request again with the assistant's name.")
        }
    }

    // MARK: - The camera loop

    /// Does what the tracker asked for. Returns the lines to say, for a command's reply.
    @discardableResult
    private func apply(_ effects: [LookTracker.Effect], tones: Bool = true) -> String {
        var lines: [String] = []
        for effect in effects {
            switch effect {
            case .tone(let tone, let target):
                if tones { play(tone, target) }
            case .say(let line):
                lines.append(line)
            case .listen:
                // After a command the conversation is already open.
                break
            }
        }
        status = tracker.status
        if tracker.isOff {
            loop?.cancel()
            loop = nil
        } else if loop == nil {
            loop = Task { [weak self] in await self?.run() }
        }
        return lines.joined(separator: " ")
    }

    private func run() async {
        var lastThumb: [UInt8] = []
        var lastReading = LookReading.empty
        var lastFresh = Date()
        var restarted = false

        while !Task.isCancelled, !tracker.isOff {
            try? await Task.sleep(for: .milliseconds(tracker.wantsCamera ? 900 : 5_000))
            guard !Task.isCancelled else { return }
            guard workshop.lookToTalk else {
                stop()
                return
            }
            tracker.rules = workshop.lookRules
            var effects: [LookTracker.Effect] = []

            if tracker.wantsCamera {
                let glasses = GlassesManager.shared
                if !glasses.isStreaming, !glasses.isPaused {
                    // Either this is the first pass, or something else took its photo and
                    // turned the camera off.
                    startedCamera = startedCamera || !cameraWantedElsewhere
                    await glasses.startStreaming(for: .lookToTalk)
                    if lastThumb.isEmpty { lastFresh = Date() }
                }
                let now = Date()
                if let image = glasses.lastFrame, now.timeIntervalSince(glasses.lastFrameTime) < 3,
                   let thumb = Thumbnail.bytes(image) {
                    lastFresh = now
                    restarted = false
                    // A frame like the last one shows what the last one showed, and reading
                    // it again would only spend the battery. It still counts as a look:
                    // holding still on a window is how one is chosen.
                    if lastThumb.isEmpty || FrameChange.difference(lastThumb, thumb) > 0.02 {
                        lastReading = await reading(of: image)
                    }
                    lastThumb = thumb
                    guard !Task.isCancelled else { return }
                    effects += tracker.looked(lastReading, at: Date())
                } else if now.timeIntervalSince(lastFresh) > 12 {
                    effects += tracker.lostCamera()
                } else if now.timeIntervalSince(lastFresh) > 6, !restarted, !glasses.isPaused {
                    restarted = true
                    await glasses.stopStreaming()
                    await glasses.startStreaming(for: .lookToTalk)
                }
            }

            effects += tracker.tick(at: Date())
            status = tracker.status
            if !tracker.wantsCamera {
                lastThumb = []
                lastReading = .empty
                await releaseCamera()
            }
            await perform(effects)
        }
        if !Task.isCancelled { loop = nil }
    }

    private func reading(of image: UIImage) async -> LookReading {
        // Little compression: small letters are what is being looked for.
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return .empty }
        let view = await AccessVision.screen(in: jpeg)
        return WindowReader.read(view, roster: workshop.lookNames(for: bots))
    }

    /// Does what the tracker asked for when nobody spoke: a tone, a line, then the microphone.
    private func perform(_ effects: [LookTracker.Effect]) async {
        for effect in effects {
            switch effect {
            case .tone(let tone, let target):
                play(tone, target)
                try? await Task.sleep(for: .milliseconds(380))
            case .say(let line):
                await quiet(atMost: 6)
                CompanionSurface.present(bot: nil, text: line) { TTSService.shared.announce($0, urgent: false) }
                // The synthesizer takes a moment to report that it has started.
                try? await Task.sleep(for: .milliseconds(300))
            case .listen:
                await quiet(atMost: 6)
                guard tracker.held != nil || tracker.question != nil else { continue }
                listen?()
            }
        }
    }

    /// Waits for whatever is being said to end.
    private func quiet(atMost seconds: Double) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, TTSService.shared.isSpeaking || NeuralSpeech.isAnySpeaking {
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    // MARK: - Sharing the camera

    private var cameraWantedElsewhere: Bool {
        cameraBusyElsewhere() || GuideMode.shared.isOn || CompanionRuntime.shared.isWatching || SmartCapture.shared.isRunning
    }

    /// Turns the camera off when this turned it on and nothing else needs it.
    private func releaseCamera() async {
        guard !tracker.wantsCamera, startedCamera else { return }
        startedCamera = false
        if GlassesManager.shared.isStreaming, !cameraWantedElsewhere {
            await GlassesManager.shared.stopStreaming()
        }
    }

    // MARK: - Tones

    private var players: [AVAudioPlayer] = []
    private var sounds: [String: Data] = [:]

    private func play(_ tone: LookTracker.Tone, _ target: LookTarget?) {
        let place = target.flatMap { target in bots.firstIndex { $0.name == target.name } }
        let key = "\(tone.rawValue)-\(place ?? -1)"
        let data = sounds[key] ?? LookTone.wav(tone, place: place)
        sounds[key] = data
        guard let player = try? AVAudioPlayer(data: data) else { return }
        // A player that is released stops, so each is kept until it has finished.
        players.removeAll { !$0.isPlaying }
        players.append(player)
        player.play()
    }
}
