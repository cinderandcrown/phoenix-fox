// Phoenix Fox turn: Whisper text is already cleaned. Short talk can use cheap Grok.
// Tasks and named assistants go to the relay. One photo, then the camera turns off.

import Foundation

@MainActor
enum PhoenixFoxTurn {
    static func run(
        cleaned: String,
        transcript: String,
        settings: AppSettings,
        snapshot: () async -> Data?,
        speakFiller: (String) -> Void,
        speak: (String, String?, Bool) -> Void
    ) async {
        let route = FastModeRouter.rules(cleaned, context: FastModeRouter.Context(
            fastMode: settings.jarvisFastMode && settings.isGrokConfigured,
            isPro: true,
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
            await relay(turn, transcript: transcript, settings: settings, snapshot: snapshot, speakFiller: speakFiller, speak: speak)
        }
    }

    private static func instant(text: String, photo: Bool, settings: AppSettings, snapshot: () async -> Data?) async {
        let image = photo ? await snapshot() : nil
        do {
            try await GrokService.shared.sendMessage(
                text,
                imageData: image,
                system: JarvisPersona.prompt(addressAsSir: settings.jarvisAddressAsSir)
            )
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
        speak: (String, String?, Bool) -> Void
    ) async {
        var images: [Data] = []
        if turn.photo, let frame = await snapshot() { images.append(frame) }
        speakFiller("On it.")
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
            for reply in replies {
                speak(reply.text, reply.fromBot, alwaysName)
            }
            let combined = replies.map(\.text).joined(separator: " ")
            ConversationContext.shared.record(user: turn.text, assistant: combined)
        } catch {
            speak(error.localizedDescription, nil, false)
        }
    }
}
