// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Provider-agnostic chat brain. The voice agent and Settings talk to `AIProvider`
// adapters; swapping Grok for Claude / OpenAI / Gemini does not change app logic.
// The Grok Bot relay (Fire Fox, Indy, Driver, Rally) stays a separate assistant route.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cloud model vendors. Not the same as `AIBackendType` (which also covers the relay,
/// Hermes, OpenClaw, and on-device brains).
enum AIProviderID: String, Codable, CaseIterable, Sendable {
    case grok
    case openAI = "openai"
    case anthropic
    case gemini

    var displayName: String {
        switch self {
        case .grok: return "Grok (xAI)"
        case .openAI: return "ChatGPT (OpenAI)"
        case .anthropic: return "Claude (Anthropic)"
        case .gemini: return "Gemini (Google)"
        }
    }

    /// Settings / Keychain account for the API key. Never log the value.
    var keychainAccount: String {
        switch self {
        case .grok: return "grokAPIKey"
        case .openAI: return "openAIAPIKey"
        case .anthropic: return "claudeAPIKey"
        case .gemini: return "geminiAPIKey"
        }
    }

    /// Maps onto the existing voice-agent backend case when this provider is the brain.
    var backendType: AIBackendType {
        switch self {
        case .grok: return .grok
        case .openAI: return .openAI
        case .anthropic: return .claude
        case .gemini: return .geminiLive
        }
    }

    static func from(backend: AIBackendType) -> AIProviderID? {
        switch backend {
        case .grok: return .grok
        case .openAI: return .openAI
        case .claude: return .anthropic
        case .geminiLive: return .gemini
        default: return nil
        }
    }
}

/// What a provider can do. Drivers check these instead of hard-coding vendor names.
struct AIProviderCapabilities: Equatable, Sendable {
    var supportsVision: Bool
    var supportsTools: Bool
    var supportsRealtimeVoice: Bool
    var supportsStreaming: Bool

    static let none = AIProviderCapabilities(
        supportsVision: false, supportsTools: false, supportsRealtimeVoice: false, supportsStreaming: false
    )
}

/// One turn in a provider chat.
struct AIChatMessage: Equatable, Sendable {
    var role: String
    var content: String
}

struct AIChatRequest: Equatable, Sendable {
    var model: String
    var messages: [AIChatMessage]
    var system: String?
    /// JPEG bytes for a look. Nil for text-only.
    var imageJPEG: Data?
    var offerTools: Bool
    var maxTokens: Int?
    /// Never log this. Passed per-call so adapters stay free of Settings.
    var apiKey: String
}

struct AIChatReply: Equatable, Sendable {
    var text: String
    var inputTokens: Int?
    var outputTokens: Int?
}

enum AIProviderError: Error, Equatable, LocalizedError {
    case notConfigured
    case missingCapability(String)
    case http(status: Int, detail: String)
    case emptyReply
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add an API key for this provider in Settings."
        case .missingCapability(let what): return "This provider cannot \(what)."
        case .http(_, let detail): return detail
        case .emptyReply: return "The provider sent an empty reply."
        case .transport(let detail): return detail
        }
    }
}

/// Injectable HTTP so adapters are unit-tested with mocked responses. Never logs bodies that may contain keys.
protocol AIHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionAITransport: AIHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

/// The swappable cloud brain. Streaming, vision, tools, and key tests live here.
/// Adapters: xAI Grok (OpenAI-compatible), OpenAI, Anthropic. Gemini is catalogued for
/// future / Live use; its HTTP chat adapter can be added without touching callers.
protocol AIProvider: Sendable {
    var id: AIProviderID { get }
    var capabilities: AIProviderCapabilities { get }
    var defaultBaseURL: String { get }

    /// Tiny authenticated request. Pass/fail only — never log the key.
    func testKey(_ key: String, transport: AIHTTPTransport) async throws

    /// One completion (optionally multimodal). Streaming variants may wrap this later.
    func complete(_ request: AIChatRequest, transport: AIHTTPTransport) async throws -> AIChatReply
}

extension AIProvider {
    func testKey(_ key: String) async throws {
        try await testKey(key, transport: URLSessionAITransport())
    }

    func complete(_ request: AIChatRequest) async throws -> AIChatReply {
        try await complete(request, transport: URLSessionAITransport())
    }
}

/// Factory — the only place vendor ids become adapter objects.
enum AIProviderRegistry {
    static func provider(for id: AIProviderID) -> any AIProvider {
        switch id {
        case .grok:
            return OpenAICompatibleProvider(
                id: .grok,
                baseURL: "https://api.x.ai/v1",
                capabilities: AIProviderCapabilities(
                    supportsVision: true, supportsTools: true,
                    supportsRealtimeVoice: false, supportsStreaming: true
                )
            )
        case .openAI:
            return OpenAICompatibleProvider(
                id: .openAI,
                baseURL: "https://api.openai.com/v1",
                capabilities: AIProviderCapabilities(
                    supportsVision: true, supportsTools: true,
                    supportsRealtimeVoice: true, supportsStreaming: true
                )
            )
        case .anthropic:
            return AnthropicProvider()
        case .gemini:
            return GeminiProviderStub()
        }
    }

    static var allCloud: [any AIProvider] {
        AIProviderID.allCases.map(provider(for:))
    }
}
