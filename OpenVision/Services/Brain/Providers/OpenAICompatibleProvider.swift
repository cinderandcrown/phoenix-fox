// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// OpenAI Chat Completions adapter. Used for xAI Grok (https://api.x.ai/v1) and OpenAI.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct OpenAICompatibleProvider: AIProvider {
    let id: AIProviderID
    let defaultBaseURL: String
    let capabilities: AIProviderCapabilities

    init(id: AIProviderID, baseURL: String, capabilities: AIProviderCapabilities) {
        self.id = id
        self.defaultBaseURL = baseURL
        self.capabilities = capabilities
    }

    func testKey(_ key: String, transport: AIHTTPTransport) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIProviderError.notConfigured }
        guard let url = URL(string: "\(defaultBaseURL)/models") else {
            throw AIProviderError.transport("Bad provider URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        // Do not log the Authorization header or the key.
        let (data, response) = try await transport.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw AIProviderError.http(status: status, detail: Self.safeDetail(from: data, status: status))
        }
    }

    func complete(_ request: AIChatRequest, transport: AIHTTPTransport) async throws -> AIChatReply {
        let key = request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIProviderError.notConfigured }
        if request.imageJPEG != nil, !capabilities.supportsVision {
            throw AIProviderError.missingCapability("accept images")
        }
        guard let url = URL(string: "\(defaultBaseURL)/chat/completions") else {
            throw AIProviderError.transport("Bad provider URL")
        }

        var messages: [[String: Any]] = []
        if let system = request.system, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        for turn in request.messages {
            messages.append(["role": turn.role, "content": turn.content])
        }

        let userContent: Any
        if let imageJPEG = request.imageJPEG {
            let dataURL = "data:image/jpeg;base64,\(imageJPEG.base64EncodedString())"
            let prompt = request.messages.last?.content ?? "Describe what you see."
            // Replace the last user text turn with multimodal content when an image is attached.
            if let last = messages.indices.last, messages[last]["role"] as? String == "user" {
                messages.remove(at: last)
            }
            userContent = [
                ["type": "text", "text": prompt.isEmpty ? "Describe what you see." : prompt],
                ["type": "image_url", "image_url": ["url": dataURL]],
            ] as [[String: Any]]
            messages.append(["role": "user", "content": userContent])
        }

        var body: [String: Any] = [
            "model": request.model,
            "messages": messages,
        ]
        if let max = request.maxTokens { body["max_tokens"] = max }
        // Tool schemas stay in CloudChat for the full agent loop; adapters expose the raw complete.

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        urlRequest.timeoutInterval = 60

        let (data, response) = try await transport.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw AIProviderError.http(status: status, detail: Self.safeDetail(from: data, status: status))
        }
        return try Self.parseChatCompletions(data)
    }

    static func parseChatCompletions(_ data: Data) throws -> AIChatReply {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = (message["content"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            throw AIProviderError.emptyReply
        }
        let usage = json["usage"] as? [String: Any]
        return AIChatReply(
            text: text,
            inputTokens: usage?["prompt_tokens"] as? Int,
            outputTokens: usage?["completion_tokens"] as? Int
        )
    }

    /// Error bodies may echo prompts; never include secrets. Strip anything that looks like a key.
    static func safeDetail(from data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return redactSecrets(message)
            }
            if let message = json["message"] as? String { return redactSecrets(message) }
        }
        return "HTTP \(status)"
    }

    static func redactSecrets(_ text: String) -> String {
        var out = text
        // xAI / OpenAI style keys
        if let regex = try? NSRegularExpression(pattern: #"(sk-|xai-)[A-Za-z0-9_\-]{8,}"#) {
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "[redacted]")
        }
        return out
    }
}
