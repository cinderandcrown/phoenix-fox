// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Phoenix Fox turn: Whisper text is already cleaned. Short talk can use cheap Grok.
// Tasks and named assistants go to the relay. One photo, then the camera turns off.

import Foundation

@MainActor
enum PhoenixFoxTurn {
    /// The part of a long answer that is waiting for "go on". Any other request drops it.
    private static var held: String?
    /// Requests acknowledged so far, so the quick word varies.
    private static var acknowledged = 0

    /// - Parameter record: Takes the whole answer as it was written, for History. What is
    ///   spoken may be shorter.
    static func run(
        cleaned: String,
        transcript: String,
        settings: AppSettings,
        snapshot: () async -> Data?,
        speakFiller: (String) -> Void,
        speak: (String, String?, Bool) -> Void,
        record: (String) -> Void = { _ in }
    ) async {
        if let waiting = held {
            held = nil
            if SpokenReply.asksForMore(cleaned) {
                let next = SpokenReply.next(of: waiting)
                held = next.later
                speak(next.now, nil, false)
                return
            }
        }
        if let line = await CompanionRuntime.shared.consume(cleaned, snapshot: snapshot) {
            if !line.isEmpty {
                speak(line, nil, false)
                note(said: cleaned, heard: line, bot: nil, saw: nil)
            }
            return
        }
        if let outcome = await PhoenixFoxFeatures.handle(cleaned, snapshot: snapshot) {
            switch outcome {
            case .spoken(let line):
                speak(line, nil, false)
                note(said: cleaned, heard: line, bot: nil, saw: nil)
                return
            case .look(let prompt):
                await instant(text: prompt, photo: true, settings: settings, snapshot: snapshot)
                return
            }
        }
        let route = FastModeRouter.rules(cleaned, context: FastModeRouter.Context(
            fastMode: settings.jarvisFastMode && settings.isGrokConfigured,
            isPro: SubscriptionStore.shared.allows(.botTeam),
            bots: settings.assistantBots,
            instantReady: settings.isGrokConfigured,
            clipEnabled: settings.jarvisLookClip
        ))
        switch route {
        case .needsPro(let message):
            speak(message, nil, false)
        case .dictate:
            speak("Go ahead.", nil, false)
        case .instant(let text, let photo, _):
            await instant(text: text, photo: photo, settings: settings, snapshot: snapshot)
        case .relay(let turn):
            await relay(turn, transcript: transcript, settings: settings, snapshot: snapshot, speakFiller: speakFiller, speak: speak, record: record)
        case .mind(let command):
            await mind(command, transcript: transcript, settings: settings, snapshot: snapshot, speakFiller: speakFiller, speak: speak, record: record)
        }
    }

    private static func mind(
        _ command: MindCommand,
        transcript: String,
        settings: AppSettings,
        snapshot: () async -> Data?,
        speakFiller: (String) -> Void,
        speak: (String, String?, Bool) -> Void,
        record: (String) -> Void
    ) async {
        let bots = settings.assistantBots.map(\.name)
        switch command {
        case .consent(true):
            SettingsManager.shared.settings.mindMeldEnabled = true
            let line = "Mind meld is on. I'll remember what you say on this phone. I won't keep a photo unless you say remember, and the capture light stays on for that shot."
            speak(line, nil, false)
        case .consent(false):
            SettingsManager.shared.settings.mindMeldEnabled = false
            MindMeld.clearPending()
            speak("Mind meld is off. I stopped the running log. Notes you asked me to remember are still on this phone.", nil, false)
        case .anticipate:
            let suggestion = MindMeld.anticipate(bots: bots)
            MindMeld.storePending(suggestion)
            speak(suggestion.spoken, suggestion.bot, false)
        case .recallSpoken:
            speak(MindMeld.recallSpoken(), nil, false)
        case .recallSeen:
            speak(MindMeld.recallSeen(), nil, false)
        case .handoff(let bot, let ask):
            let text = MindMeldPlanner.handoffAsk(pending: MindMeld.pending(), episodes: MindMeld.episodes(), explicit: ask)
            guard let text, !text.isEmpty else {
                speak("There's nothing waiting. Tell me what you want \(bot) to do.", nil, false)
                return
            }
            MindMeld.clearPending()
            await relay(
                RelayTurn(intent: "message", targetBot: bot, text: text, photo: false, clip: false, cacheable: false),
                transcript: transcript,
                settings: settings,
                snapshot: snapshot,
                speakFiller: speakFiller,
                speak: speak,
                record: record
            )
        }
    }

    private static func note(said: String, heard: String?, bot: String?, saw: String?) {
        guard SettingsManager.shared.settings.mindMeldEnabled else { return }
        MindMeld.note(said: said, heard: heard, bot: bot, saw: saw)
    }

    private static func instant(text: String, photo: Bool, settings: AppSettings, snapshot: () async -> Data?) async {
        let image = photo ? await snapshot() : nil
        do {
            try await GrokService.shared.sendMessage(
                text,
                imageData: image,
                system: JarvisPersona.prompt(addressAsSir: settings.jarvisAddressAsSir)
            )
            note(said: text, heard: nil, bot: nil, saw: photo ? text : nil)
        } catch {
            TTSService.shared.speak("I couldn't reach the fast model.")
        }
    }

    private static func relay(
        _ turn: RelayTurn,
        transcript: String,
        settings: AppSettings,
        snapshot: () async -> Data?,
        speakFiller: (String) -> Void,
        speak: (String, String?, Bool) -> Void,
        record: (String) -> Void
    ) async {
        // The quick word comes first, before the photo is taken, so the wearer hears at once
        // that the request landed and where it went.
        speakFiller(Acknowledgement.line(targetBot: turn.targetBot, bots: settings.assistantBots, photo: turn.photo, turn: acknowledged))
        acknowledged += 1
        var images: [Data] = []
        if turn.photo, let frame = await snapshot() { images.append(frame) }
        do {
            let replies = try await OwnAssistantService.shared.ask(
                transcript: transcript,
                cleaned: turn.text,
                images: images,
                intent: turn.intent,
                targetBot: turn.targetBot
            )
            let alwaysName = turn.targetBot == AssistantBot.allBots || replies.count > 1
            if replies.isEmpty {
                speak("Nothing came back.", nil, false)
                return
            }
            // History keeps every word. The voice gets plain words and a short first part.
            record(replies.count == 1 ? replies[0].text : replies.map { "\($0.fromBot): \($0.text)" }.joined(separator: "\n"))
            let shaped = SpokenReply.turn(replies.map { (text: $0.text, from: $0.fromBot) }, short: settings.shortSpokenReplies)
            held = shaped.later
            for line in shaped.lines {
                speak(line.text, replies[line.index].fromBot, alwaysName)
            }
            let combined = replies.map(\.text).joined(separator: " ")
            ConversationContext.shared.record(user: turn.text, assistant: combined)
            note(
                said: turn.text,
                heard: combined,
                bot: replies.count == 1 ? replies[0].fromBot : turn.targetBot,
                saw: turn.photo ? turn.text : nil
            )
        } catch is CancellationError {
            // The wearer stopped it. Saying so would talk over whatever they did next.
        } catch {
            speak(error.localizedDescription, nil, false)
        }
    }
}
