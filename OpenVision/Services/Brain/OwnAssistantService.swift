// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Phoenix Fox - the relay client for Fire Fox, Indy, Driver, and Rally.
// The URL and bearer token come from Settings. Neither is in the repo.

import Foundation

/// Last push the inbox delivered, so "reply …" can thread a new ask back to that bot.
@MainActor
enum InboxThread {
    static var lastId: String?
    static var lastFrom: String?
}

/// The wearer's own assistants, reached through the relay.
///
/// This type owns what is particular to the app: the settings, the conversation context,
/// the inbox loop, and stopping work when the wearer interrupts. The HTTP is `RelayClient`.
@MainActor
final class OwnAssistantService: ObservableObject {
    static let shared = OwnAssistantService()

    var onAgentMessage: ((String) -> Void)?
    var onProcessingChanged: ((Bool) -> Void)?
    @Published private(set) var isConnected = false

    private let client: RelayClient
    /// Asks that are waiting for a reply, each with the way to stop it.
    private var inFlight: [UUID: @Sendable () -> Void] = [:]
    private var inboxTask: Task<Void, Never>?
    private var push = PushRegistration()
    private var settings: AppSettings { SettingsManager.shared.settings }

    init(client: RelayClient = RelayClient()) {
        self.client = client
    }

    // MARK: Asking

    func connect() async throws {
        guard settings.relayEndpoint != nil else { throw RelayError.notConfigured }
        isConnected = true
    }

    /// Stops every ask that is waiting for a reply. The wearer said stop, or started over.
    func interrupt() {
        let stops = Array(inFlight.values)
        inFlight.removeAll()
        stops.forEach { $0() }
    }

    func sendMessage(_ text: String, imageData: Data? = nil) async throws {
        let replies = try await ask(
            transcript: text,
            cleaned: text,
            images: imageData.map { [$0] } ?? [],
            intent: "message",
            targetBot: AssistantRoster.defaultBot(in: settings.assistantBots).name
        )
        onAgentMessage?(replies.map(\.text).joined(separator: " "))
    }

    func ask(
        transcript: String,
        cleaned: String,
        images: [Data],
        intent: String,
        targetBot: String,
        replyTo: String? = nil
    ) async throws -> [RelayReply] {
        guard let endpoint = settings.relayEndpoint else { throw RelayError.notConfigured }
        let ask = RelayAsk(
            text: cleaned,
            transcript: transcript,
            intent: intent,
            targetBot: targetBot,
            context: recentContext(),
            replyTo: replyTo,
            images: RelayImages.fitted(images, budget: RelayClient.imageBudget)
        )
        onProcessingChanged?(true)
        defer { onProcessingChanged?(false) }
        let client = self.client
        // The home screen shows who has been asked and who has answered.
        let board = TeamBoardStore.shared
        board.sync(roster: settings.assistantBots)
        board.asked(targetBot, task: cleaned)
        do {
            let replies = try await value(of: Task { try await client.ask(ask, to: endpoint) })
            for reply in replies {
                board.answered(by: reply.fromBot.isEmpty ? targetBot : reply.fromBot, text: reply.text)
            }
            board.settled(targetBot)
            return replies
        } catch let stopped as CancellationError {
            board.settled(targetBot)
            throw stopped
        } catch {
            board.failed(targetBot, reason: error.localizedDescription)
            throw error
        }
    }

    /// Asks every bot at the same time. `onEach` runs as that bot's reply arrives, so speech
    /// can start before the slowest one finishes. A bot that fails or is stopped reports "".
    ///
    /// - Parameter images: Pictures every bot is sent with the question.
    func askEach(
        transcript: String,
        cleaned: String,
        intent: String,
        bots: [String],
        images: [Data] = [],
        onEach: @MainActor (String, String) -> Void
    ) async {
        guard let endpoint = settings.relayEndpoint else { return }
        let context = recentContext()
        let client = self.client
        let pictures = RelayImages.fitted(images, budget: RelayClient.imageBudget)
        let (answers, continuation) = AsyncStream.makeStream(of: (bot: String, text: String).self)
        let task = Task {
            await withTaskGroup(of: (bot: String, text: String).self) { group in
                for bot in bots {
                    group.addTask {
                        let ask = RelayAsk(
                            text: cleaned, transcript: transcript, intent: intent, targetBot: bot, context: context, images: pictures
                        )
                        let replies = (try? await client.ask(ask, to: endpoint)) ?? []
                        return (bot, replies.map(\.text).joined(separator: " "))
                    }
                }
                for await answer in group {
                    continuation.yield(answer)
                }
            }
            continuation.finish()
        }
        let id = UUID()
        inFlight[id] = { task.cancel() }
        defer { inFlight[id] = nil }
        // The stream also ends when this caller is cancelled, so the bots are stopped either way.
        defer { task.cancel() }
        let board = TeamBoardStore.shared
        board.sync(roster: settings.assistantBots)
        for bot in bots { board.asked(bot, task: cleaned) }
        defer { for bot in bots { board.settled(bot) } }
        for await answer in answers {
            board.answered(by: answer.bot, text: answer.text)
            onEach(answer.bot, answer.text)
        }
    }

    /// Waits for relay work that `interrupt()` can stop, and that stops with its caller.
    private func value<Value: Sendable>(of task: Task<Value, any Error>) async throws -> Value {
        let id = UUID()
        inFlight[id] = { task.cancel() }
        defer { inFlight[id] = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func recentContext() -> [RelayAsk.Turn] {
        ConversationContext.shared.turns.suffix(8).map { RelayAsk.Turn(role: $0.role, text: $0.content) }
    }

    // MARK: Inbox and push

    /// Long-poll `/inbox` while the relay is configured. A push from Apple, when the phone
    /// has a token, only wakes this same pull. Nothing is spoken if the relay is down.
    func startInbox() {
        guard inboxTask == nil else { return }
        inboxTask = Task { await inboxLoop() }
    }

    /// Apple gave this phone a push token.
    func registerDevice(_ token: String) async {
        push.received(token: token)
        await registerDeviceIfNeeded()
    }

    /// Gives the relay this phone's push token if it does not have it yet.
    /// Called when the token arrives, when the relay settings are saved, and after the inbox
    /// reaches the relay, so a send that failed is tried again once the relay answers.
    func registerDeviceIfNeeded() async {
        guard let send = push.pending(for: settings.relayEndpoint) else { return }
        do {
            try await client.registerDevice(token: send.token, environment: .current, with: send.endpoint)
            push.accepted(send)
        } catch {
            GlassesLink.shared.record("Push registration with the relay failed: \(error.localizedDescription)")
        }
    }

    func pullInboxOnce() async {
        guard let endpoint = settings.relayEndpoint else { return }
        guard let items = try? await client.inbox(from: endpoint) else { return }
        deliver(items)
    }

    /// Checks the relay with the address and token as typed, before they are saved.
    func check(address: String, token: String) async -> Result<RelayHealth, RelayError> {
        guard let endpoint = RelayEndpoint(address: address, token: token) else { return .failure(.notConfigured) }
        do {
            return .success(try await client.health(of: endpoint))
        } catch let error as RelayError {
            return .failure(error)
        } catch {
            return .failure(.server(status: 0))
        }
    }

    private func inboxLoop() async {
        var backoff: Duration = .seconds(2)
        while !Task.isCancelled {
            guard let endpoint = settings.relayEndpoint else {
                try? await Task.sleep(for: .seconds(5))
                continue
            }
            do {
                deliver(try await client.inbox(from: endpoint))
                backoff = .seconds(1)
                await registerDeviceIfNeeded()
            } catch RelayError.unauthorized {
                // A wrong token will not start working by itself. Look again when Settings may have changed.
                try? await Task.sleep(for: .seconds(60))
            } catch RelayError.rateLimited(let retryAfter) {
                try? await Task.sleep(for: .seconds(retryAfter))
            } catch {
                try? await Task.sleep(for: backoff)
                backoff = min(backoff * 2, .seconds(30))
            }
        }
    }

    private func deliver(_ items: [RelayPush]) {
        for item in items {
            InboxThread.lastId = item.id
            InboxThread.lastFrom = item.fromBot
            if item.priority != .low {
                TeamBoardStore.shared.alerted(by: item.fromBot, text: item.text, urgent: item.priority == .urgent)
            }
            CompanionRuntime.shared.notePush(text: item.text, from: item.fromBot.isEmpty ? "Fire Fox" : item.fromBot, priority: item.priority.rawValue)
        }
    }
}
