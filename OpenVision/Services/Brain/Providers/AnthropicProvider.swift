// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Anthropic Messages API adapter. Real against https://api.anthropic.com/v1.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct AnthropicProvider: AIProvider {
    let id: AIProviderID = .anthropic
    let defaultBaseURL = "https://api.anthropic.com/v1"
    let capabilities = AIProviderCapabilities(
        supportsVision: true, supportsTools: true,
        supportsRealtimeVoice: false, supportsStreaming: true
    )

    private let apiVersion = "2023-06-01"

    func testKey(_ key: String, transport: AIHTTPTransport) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIProviderError.notConfigured }
        // Tiny Messages call — models list needs a different auth shape on some plans.
        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]],
        ]
        var request = URLRequest(url: URL(string: "\(defaultBaseURL)/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmed, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        let (data, response) = try await transport.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw AIProviderError.http(
                status: status,
                detail: OpenAICompatibleProvider.safeDetail(from: data, status: status)
            )
        }
    }

    func complete(_ request: AIChatRequest, transport: AIHTTPTransport) async throws -> AIChatReply {
        let key = request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIProviderError.notConfigured }
        if request.imageJPEG != nil, !capabilities.supportsVision {
            throw AIProviderError.missingCapability("accept images")
        }

        var content: [[String: Any]] = []
        if let imageJPEG = request.imageJPEG {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": imageJPEG.base64EncodedString(),
                ],
            ])
        }
        let prompt = request.messages.last(where: { $0.role == "user" })?.content
            ?? request.messages.last?.content
            ?? ""
        content.append(["type": "text", "text": prompt.isEmpty ? "Describe what you see." : prompt])

        var messages: [[String: Any]] = []
        for turn in request.messages.dropLast(request.messages.last?.role == "user" ? 1 : 0) {
            guard turn.role == "user" || turn.role == "assistant" else { continue }
            messages.append(["role": turn.role, "content": turn.content])
        }
        messages.append(["role": "user", "content": content])

        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens ?? 300,
            "messages": messages,
        ]
        if let system = request.system, !system.isEmpty {
            body["system"] = [
                ["type": "text", "text": system, "cache_control": ["type": "ephemeral"]],
            ]
        }

        var urlRequest = URLRequest(url: URL(string: "\(defaultBaseURL)/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        urlRequest.timeoutInterval = 60

        let (data, response) = try await transport.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw AIProviderError.http(
                status: status,
                detail: OpenAICompatibleProvider.safeDetail(from: data, status: status)
            )
        }
        return try Self.parseMessages(data)
    }

    static func parseMessages(_ data: Data) throws -> AIChatReply {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]]
        else {
            throw AIProviderError.emptyReply
        }
        let text = blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIProviderError.emptyReply }
        let usage = json["usage"] as? [String: Any]
        return AIChatReply(
            text: text,
            inputTokens: usage?["input_tokens"] as? Int,
            outputTokens: usage?["output_tokens"] as? Int
        )
    }
}

/// Placeholder so the catalog can list Gemini without pretending HTTP chat is wired.
/// Realtime / Live stays on `GeminiLiveService`. A full chat adapter can replace this later.
struct GeminiProviderStub: AIProvider {
    let id: AIProviderID = .gemini
    let defaultBaseURL = "https://generativelanguage.googleapis.com/v1beta"
    let capabilities = AIProviderCapabilities(
        supportsVision: true, supportsTools: true,
        supportsRealtimeVoice: true, supportsStreaming: true
    )

    func testKey(_ key: String, transport: AIHTTPTransport) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIProviderError.notConfigured }
        // A missing chat adapter still validates that a key was saved.
        _ = transport
    }

    func complete(_ request: AIChatRequest, transport: AIHTTPTransport) async throws -> AIChatReply {
        _ = request
        _ = transport
        throw AIProviderError.missingCapability("chat completions yet — use Gemini Live for realtime, or pick Grok / Claude / OpenAI")
    }
}
