// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Guide mode: spoken callouts of what the glasses camera sees while the wearer walks.
//
// Detection runs on the phone about once a second: people, animals, stairs, doors,
// vehicles, and large signs. When the scene changes a lot, one frame may also go to a
// vision model for hazards the phone cannot detect, if the wearer allows it. The capture
// light on the glasses is on for as long as Guide mode is on.
//
// It is an aid. A single forward camera at eight frames a second cannot measure distance
// and will miss curbs, drop-offs, glass, and fast traffic. The safety notice says so
// before the first use, and the docs say it again.

import AVFoundation
import Foundation
import UIKit

@MainActor
final class GuideMode: ObservableObject {
    static let shared = GuideMode()

    @Published private(set) var isOn = false

    static let safetyNotice = "Before Guide mode starts: it calls out people, vehicles, stairs, doors, and signs that the glasses camera can see. It is an aid. It will miss things, especially curbs, drop-offs, glass, and fast traffic, and it does not replace a cane, a guide dog, or your own judgment. The camera light on the glasses stays on while it runs."

    private var loop: Task<Void, Never>?
    private var modelBusy = false

    private init() {}

    func start() -> String {
        guard !isOn else { return "Guide mode is already on." }
        guard GlassesManager.shared.isRegistered else {
            return "Guide mode needs the glasses camera. Connect the glasses first."
        }
        isOn = true
        CompanionRuntime.shared.showGuide(on: true)
        loop = Task { [weak self] in await self?.run() }
        return "Guide mode is on, and the camera light is on. Keep using your cane or your dog. Say stop guide mode when you're done."
    }

    func stop() -> String {
        guard isOn else { return "Guide mode is already off." }
        isOn = false
        loop?.cancel()
        loop = nil
        CompanionRuntime.shared.showGuide(on: false)
        // Watch mode and Smart Capture share the camera. It stays on if either still needs it.
        if !CompanionRuntime.shared.isWatching && !SmartCapture.shared.isRunning {
            Task { await GlassesManager.shared.stopStreaming() }
            return "Guide mode is off, and the camera is off."
        }
        return "Guide mode is off. The camera is still on for the other thing you started."
    }

    private func run() async {
        await GlassesManager.shared.startStreaming()
        var narrator = GuideNarrator()
        var lastThumb: [UInt8] = []
        var lastModel = Date.distantPast
        var modelCalls = 0
        var lastFaces = Date.distantPast
        var greeted: [String: Date] = [:]
        var quietTicks = 0
        var staleTicks = 0
        var saidLost = false

        while !Task.isCancelled, isOn {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, isOn else { break }

            let manager = GlassesManager.shared
            guard let image = manager.lastFrame, Date().timeIntervalSince(manager.lastFrameTime) < 3,
                  let thumb = Thumbnail.bytes(image) else {
                staleTicks += 1
                // Something else may have turned the camera off after taking its own photo.
                if staleTicks % 3 == 0, !manager.isStreaming { await manager.startStreaming() }
                if staleTicks == 8, !saidLost {
                    saidLost = true
                    TTSService.shared.announce("I've lost the glasses camera, so I can't guide right now. I'll tell you when it's back.", urgent: true)
                }
                continue
            }
            if saidLost {
                saidLost = false
                TTSService.shared.announce("The camera is back.", urgent: false)
            }
            staleTicks = 0

            // A frame that looks like the last one has nothing new to say. It is skipped,
            // but never more than three times in a row: something can approach slowly.
            let change = FrameChange.difference(lastThumb, thumb)
            lastThumb = thumb
            if change < 0.03, quietTicks < 3 {
                quietTicks += 1
                continue
            }
            quietTicks = 0

            guard let jpeg = image.jpegData(compressionQuality: 0.6) else { continue }
            let now = Date()
            let sightings = await AccessVision.sightings(in: jpeg)
            let settings = SettingsManager.shared.settings
            // While the wearer is giving a command, only an urgent callout talks over them.
            let voice = VoiceCommandService.shared.state
            let wearerHasTheFloor = voice == .listening || voice == .conversationMode
            for callout in narrator.callouts(for: sightings, at: now) where callout.urgent || !wearerHasTheFloor {
                say(callout, cues: settings.accessibility.guideAudioCues)
            }

            if settings.accessibility.faceRecognition, now.timeIntervalSince(lastFaces) > 6,
               sightings.contains(where: { $0.kind == .person }), !AccessFaces.shared.records.isEmpty {
                lastFaces = now
                let names = await AccessFaces.shared.identify(jpeg: jpeg).names
                for name in names where now.timeIntervalSince(greeted[name] ?? .distantPast) > 120 {
                    greeted[name] = now
                    TTSService.shared.announce("\(name) is here.", urgent: false)
                    AccessibilityCoordinator.shared.saw(name)
                }
            }

            // The model is asked only on a real change of scene, never more often than
            // every twelve seconds, and at most sixty times in a session.
            let canAsk = settings.accessibility.guideCloudDescriptions && !modelBusy && modelCalls < 60
                && change > FrameChange.sceneChangeThreshold && now.timeIntervalSince(lastModel) > 12
            if canAsk, let small = ImageBudget.jpeg(jpeg) {
                lastModel = now
                modelCalls += 1
                modelBusy = true
                Task { [weak self] in
                    let hazard = await SceneDescriber.hazards(in: small)
                    guard let self else { return }
                    self.modelBusy = false
                    if let hazard, self.isOn { TTSService.shared.announce(hazard, urgent: false) }
                }
            }
        }
    }

    private func say(_ callout: Callout, cues: Bool) {
        if cues { CuePlayer.play(side: callout.side, urgent: callout.urgent) }
        CompanionRuntime.shared.caption = callout.text
        // An urgent callout interrupts whatever is being said. The rest wait for quiet.
        TTSService.shared.announce(callout.text, urgent: callout.urgent)
    }
}

/// Describes a photo with the best model available, on the phone first.
enum SceneDescriber {
    private static let scenePrompt = "Describe this scene for a blind person in two or three short sentences. Start with anything that affects safe movement, then the layout, then people and any readable text. Say only what is clearly visible."
    private static let hazardPrompt = "You are helping a blind pedestrian. In one short sentence, name only hazards within a few steps: stairs, a curb or drop, a pole, a low obstacle, a door, or a vehicle, and say whether it is left, ahead, or right. If there is none, answer with the single word clear."

    /// A full description, or nil when no model can be reached.
    @MainActor
    static func scene(in jpeg: Data) async -> String? {
        await ask(scenePrompt, jpeg: jpeg, tokens: 90)
    }

    /// A hazard to call out, or nil when the model saw none or could not be reached.
    @MainActor
    static func hazards(in jpeg: Data) async -> String? {
        guard let answer = await ask(hazardPrompt, jpeg: jpeg, tokens: 40) else { return nil }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("clear") || trimmed.isEmpty ? nil : trimmed
    }

    /// Where something is, for "find the …" when the phone's own detectors did not see it.
    @MainActor
    static func locate(_ thing: String, in jpeg: Data) async -> String? {
        let prompt = "Is there a \(thing) in this photo? If so, say in one short sentence whether it is to the left, ahead, or to the right, and roughly how far. If not, answer with the single word no."
        guard let answer = await ask(prompt, jpeg: jpeg, tokens: 40) else { return nil }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("no") || trimmed.isEmpty ? nil : trimmed
    }

    /// The on-device vision model when one is loaded, which costs nothing and works with no
    /// signal. Otherwise the fast cloud model, when a key is set.
    @MainActor
    private static func ask(_ prompt: String, jpeg: Data, tokens: Int) async -> String? {
        if GemmaLocalService.shared.visionReady,
           let local = try? await GemmaLocalService.shared.describeFrame(jpeg, prompt: prompt, maxTokens: tokens), !local.isEmpty {
            return local
        }
        guard SettingsManager.shared.settings.isGrokConfigured else { return nil }
        let system = "You are the eyes of a blind person. Be brief, concrete, and never guess."
        return try? await GrokService.shared.complete(prompt, imageData: jpeg, system: system)
    }
}

/// Plays the short direction tones that come before a spoken callout.
@MainActor
enum CuePlayer {
    private static var players: [AVAudioPlayer] = []
    private static var sounds: [String: Data] = [:]

    static func play(side: Side?, urgent: Bool) {
        let key = "\(side?.rawValue ?? "unknown")-\(urgent)"
        let data = sounds[key] ?? CueTone.wav(CueTone.samples(CueTone.segments(side: side, urgent: urgent)))
        sounds[key] = data
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.pan = side?.pan ?? 0
        // A player that is released stops, so each is kept until it has finished.
        players.removeAll { !$0.isPlaying }
        players.append(player)
        player.play()
    }
}
