// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Phoenix Fox - the relay client for Fire Fox, Indy, Driver, and Rally.
// The URL and bearer token come from Settings. Neither is in the repo.

import Foundation

struct RelayReply: Equatable {
    var text: String
    var fromBot: String
}

@MainActor
final class OwnAssistantService: ObservableObject {
    static let shared = OwnAssistantService()

    var onAgentMessage: ((String) -> Void)?
    var onProcessingChanged: ((Bool) -> Void)?
    @Published private(set) var isConnected = false

    private var generation = 0
    private var settings: AppSettings { SettingsManager.shared.settings }
    private init() {}

    func connect() async throws {
        guard settings.isOwnAssistantConfigured else { throw RelayError.notConfigured }
        isConnected = true
    }

    func interrupt() { generation += 1 }

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

    func ask(transcript: String, cleaned: String, images: [Data], intent: String, targetBot: String) async throws -> [RelayReply] {
        guard settings.isOwnAssistantConfigured else { throw RelayError.notConfigured }
        let token = generation
        onProcessingChanged?(true)
        defer { onProcessingChanged?(false) }

        let id = UUID().uuidString
        var body: [String: Any] = [
            "id": id,
            "text": cleaned,
            "transcript": transcript,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "intent": intent,
            "target_bot": targetBot,
            "context": ConversationContext.shared.turns.suffix(8).map {
                ["role": $0.role, "text": $0.content]
            },
        ]
        if let first = images.first {
            body["image"] = first.base64EncodedString()
        }
        if images.count > 1 {
            body["images"] = images.map { $0.base64EncodedString() }
        }
        let base = settings.relayURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: URL(string: "\(base)/ask")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.relayToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw RelayError.http(status) }

        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if generation != token { throw RelayError.cancelled }
            if let ready = try await poll(base: base, id: id) { return ready }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        throw RelayError.timeout
    }

    private func poll(base: String, id: String) async throws -> [RelayReply]? {
        var request = URLRequest(url: URL(string: "\(base)/reply/\(id)?wait=20")!)
        request.setValue("Bearer \(settings.relayToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw RelayError.http(status) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let state = json["status"] as? String ?? ""
        guard state == "ready" else { return nil }
        if let parts = json["replies"] as? [[String: Any]], !parts.isEmpty {
            return parts.compactMap { part in
                guard let text = part["text"] as? String, !text.isEmpty else { return nil }
                return RelayReply(text: text, fromBot: part["from_bot"] as? String ?? "")
            }
        }
        guard let text = json["text"] as? String, !text.isEmpty else { return nil }
        return [RelayReply(text: text, fromBot: json["from_bot"] as? String ?? "")]
    }

    enum RelayError: LocalizedError {
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
}
