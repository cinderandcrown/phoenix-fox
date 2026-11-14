// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Jarvis - ClaudeService.swift
// Anthropic Messages API. A peer of Grok and OpenAI, not a special case.
// https://docs.anthropic.com/en/api/messages

import Foundation

@MainActor
final class ClaudeService: ObservableObject {
    static let shared = ClaudeService()

    var onAgentMessage: ((String) -> Void)?
    var onProcessingChanged: ((Bool) -> Void)?
    @Published private(set) var isConnected = false

    private var settings: AppSettings { SettingsManager.shared.settings }
    private init() {}

    func connect() async throws {
        guard settings.isClaudeConfigured else { throw ClaudeError.notConfigured }
        isConnected = true
    }

    func sendMessage(_ text: String, imageData: Data? = nil) async throws {
        let reply = try await complete(text: text, imageJPEG: imageData, system: JarvisPersona.prompt(addressAsSir: settings.jarvisAddressAsSir))
        ConversationContext.shared.record(user: text, assistant: reply)
        onAgentMessage?(reply)
    }

    /// One-shot used by fast mode. Does not touch the shared callbacks, so the conductor speaks once.
    func complete(text: String, imageJPEG: Data?, system: String) async throws -> String {
        guard settings.isClaudeConfigured else { throw ClaudeError.notConfigured }
        onProcessingChanged?(true)
        defer { onProcessingChanged?(false) }

        var content: [[String: Any]] = []
        if let imageJPEG {
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": imageJPEG.base64EncodedString()],
            ])
        }
        content.append(["type": "text", "text": text.isEmpty ? "Describe what you see." : text])

        var messages: [[String: Any]] = ConversationContext.shared.turns.map {
            ["role": $0.role == "assistant" ? "assistant" : "user", "content": $0.content]
        }
        messages.append(["role": "user", "content": content])

        let body: [String: Any] = [
            "model": InstantModels.id(for: .claude, settings: settings),
            "max_tokens": 300,
            "system": system,
            "messages": messages,
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(settings.claudeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw ClaudeError.request(Self.message(from: data) ?? "HTTP \(status)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else {
            throw ClaudeError.request("Empty reply")
        }
        let reply = blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw ClaudeError.request("Empty reply") }
        return reply
    }

    private static func message(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return nil
    }

    enum ClaudeError: LocalizedError {
        case notConfigured
        case request(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Claude isn't configured. Add an Anthropic API key in Settings."
            case .request(let message): return message
            }
        }
    }
}
