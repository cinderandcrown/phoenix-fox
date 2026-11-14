// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Phoenix Fox - the relay client for Fire Fox, Indy, Driver, and Rally.
// The URL and bearer token come from Settings. Neither is in the repo.

import Foundation

struct RelayReply: Equatable, Sendable {
    var text: String
    var fromBot: String
}

/// Last push the inbox delivered, so "reply …" can thread a new ask back to that bot.
@MainActor
enum InboxThread {
    static var lastId: String?
    static var lastFrom: String?
}

enum RelayFailure: LocalizedError {
    case notConfigured, http(Int), timeout, cancelled
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add the relay address and token in Settings."
        case .http(let code): return "The relay returned \(code)."
        case .timeout: return "No reply within 90 seconds."
        case .cancelled: return "Stopped."
        }
    }
}

/// Relay HTTP that can run off the main actor, so four bots can be asked at once.
enum RelayHTTP {
    struct Push: Sendable {
        var id: String
        var text: String
        var fromBot: String
        var priority: String
    }

    static func ask(
        base: String,
        bearer: String,
        transcript: String,
        cleaned: String,
        images: [Data],
        intent: String,
        targetBot: String,
        context: [[String: String]],
        replyTo: String?,
        isCancelled: @Sendable () -> Bool
    ) async throws -> [RelayReply] {
        let root = trimmed(base)
        guard let askURL = URL(string: "\(root)/ask") else { throw RelayFailure.notConfigured }
        let id = UUID().uuidString
        var body: [String: Any] = [
            "id": id,
            "text": cleaned,
            "transcript": transcript,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "intent": intent,
            "target_bot": targetBot,
            "context": context,
        ]
        if let replyTo { body["reply_to"] = replyTo }
        if let first = images.first { body["image"] = first.base64EncodedString() }
        if images.count > 1 { body["images"] = images.map { $0.base64EncodedString() } }
        var request = URLRequest(url: askURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw RelayFailure.http(status) }

        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if isCancelled() { throw RelayFailure.cancelled }
            if let ready = try await poll(root: root, bearer: bearer, id: id) { return ready }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        throw RelayFailure.timeout
    }

    static func inbox(base: String, bearer: String) async throws -> [Push] {
        let root = trimmed(base)
        guard let url = URL(string: "\(root)/inbox?wait=25") else { throw RelayFailure.notConfigured }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 40
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw RelayFailure.http(status) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        if let parts = json["messages"] as? [[String: Any]] {
            return parts.compactMap(push)
        }
        if let one = push(json) { return [one] }
        return []
    }

    static func registerDevice(base: String, bearer: String, token: String) async {
        let root = trimmed(base)
        guard let url = URL(string: "\(root)/device") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token, "platform": "ios"])
        request.timeoutInterval = 20
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func poll(root: String, bearer: String, id: String) async throws -> [RelayReply]? {
        guard let url = URL(string: "\(root)/reply/\(id)?wait=20") else { throw RelayFailure.notConfigured }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw RelayFailure.http(status) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard (json["status"] as? String ?? "") == "ready" else { return nil }
        if let parts = json["replies"] as? [[String: Any]], !parts.isEmpty {
            return parts.compactMap { part in
                guard let text = part["text"] as? String, !text.isEmpty else { return nil }
                return RelayReply(text: text, fromBot: part["from_bot"] as? String ?? "")
            }
        }
        guard let text = json["text"] as? String, !text.isEmpty else { return nil }
        return [RelayReply(text: text, fromBot: json["from_bot"] as? String ?? "")]
    }

    private static func push(_ json: [String: Any]) -> Push? {
        guard let text = json["text"] as? String, !text.isEmpty else { return nil }
        return Push(
            id: json["id"] as? String ?? UUID().uuidString,
            text: text,
            fromBot: json["from_bot"] as? String ?? "Fire Fox",
            priority: json["priority"] as? String ?? "normal"
        )
    }

    private static func trimmed(_ base: String) -> String {
        base.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

@MainActor
final class OwnAssistantService: ObservableObject {
    static let shared = OwnAssistantService()

    var onAgentMessage: ((String) -> Void)?
    var onProcessingChanged: ((Bool) -> Void)?
    @Published private(set) var isConnected = false

    private var cancelFlag = CancelFlag()
    private var inboxTask: Task<Void, Never>?
    private var settings: AppSettings { SettingsManager.shared.settings }
    private init() {}

    /// Long-poll `/inbox` while the relay is configured. APNs, when the phone has a token,
    /// only wakes this same pull. Nothing is spoken if the relay is down.
    func startInbox() {
        guard inboxTask == nil else { return }
        inboxTask = Task { await inboxLoop() }
    }

    func registerDevice(_ token: String) async {
        guard settings.isOwnAssistantConfigured else { return }
        await RelayHTTP.registerDevice(base: settings.relayURL, bearer: settings.relayToken, token: token)
    }

    func pullInboxOnce() async {
        guard settings.isOwnAssistantConfigured else { return }
        guard let items = try? await RelayHTTP.inbox(base: settings.relayURL, bearer: settings.relayToken) else { return }
        deliver(items)
    }

    func connect() async throws {
        guard settings.isOwnAssistantConfigured else { throw RelayFailure.notConfigured }
        isConnected = true
    }

    func interrupt() {
        cancelFlag.cancel()
        cancelFlag = CancelFlag()
    }

    func sendMessage(_ text: String, imageData: Data? = nil) async throws {
        let replies = try await ask(
            transcript: text,
            cleaned: text,
            images: imageData.map { [$0] } ?? [],
            intent: "message",
            targetBot: AssistantRoster.defaultBot(in: settings.assistantBots).name
        )
        let spoken = replies.map(\.text).joined(separator: " ")
        onAgentMessage?(spoken)
    }

    func ask(
        transcript: String,
        cleaned: String,
        images: [Data],
        intent: String,
        targetBot: String,
        replyTo: String? = nil
    ) async throws -> [RelayReply] {
        guard settings.isOwnAssistantConfigured else { throw RelayFailure.notConfigured }
        let flag = cancelFlag
        onProcessingChanged?(true)
        defer { onProcessingChanged?(false) }
        return try await RelayHTTP.ask(
            base: settings.relayURL,
            bearer: settings.relayToken,
            transcript: transcript,
            cleaned: cleaned,
            images: images,
            intent: intent,
            targetBot: targetBot,
            context: recentContext(),
            replyTo: replyTo,
            isCancelled: { flag.isCancelled }
        )
    }

    /// Asks every bot at the same time. `onEach` runs as that bot's reply arrives, so speech
    /// can start before the slowest one finishes.
    func askEach(
        transcript: String,
        cleaned: String,
        intent: String,
        bots: [String],
        onEach: @escaping @MainActor (String, String) -> Void
    ) async {
        guard settings.isOwnAssistantConfigured else { return }
        let base = settings.relayURL
        let bearer = settings.relayToken
        let context = recentContext()
        let flag = cancelFlag
        await withTaskGroup(of: (String, String).self) { group in
            for bot in bots {
                group.addTask {
                    do {
                        let replies = try await RelayHTTP.ask(
                            base: base,
                            bearer: bearer,
                            transcript: transcript,
                            cleaned: cleaned,
                            images: [],
                            intent: intent,
                            targetBot: bot,
                            context: context,
                            replyTo: nil,
                            isCancelled: { flag.isCancelled }
                        )
                        let text = replies.map(\.text).joined(separator: " ")
                        return (bot, text)
                    } catch {
                        return (bot, "")
                    }
                }
            }
            for await (bot, text) in group {
                onEach(bot, text)
            }
        }
    }

    private func recentContext() -> [[String: String]] {
        ConversationContext.shared.turns.suffix(8).map { ["role": $0.role, "text": $0.content] }
    }

    private func inboxLoop() async {
        var backoff: UInt64 = 2_000_000_000
        while !Task.isCancelled {
            guard settings.isOwnAssistantConfigured else {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            }
            do {
                let items = try await RelayHTTP.inbox(base: settings.relayURL, bearer: settings.relayToken)
                backoff = 1_000_000_000
                deliver(items)
            } catch {
                try? await Task.sleep(nanoseconds: backoff)
                backoff = min(backoff * 2, 30_000_000_000)
            }
        }
    }

    private func deliver(_ items: [RelayHTTP.Push]) {
        for item in items {
            InboxThread.lastId = item.id
            InboxThread.lastFrom = item.fromBot
            CompanionRuntime.shared.notePush(text: item.text, from: item.fromBot, priority: item.priority)
        }
    }
}

/// Shared cancel token so parallel relay calls stop together when the wearer interrupts.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
