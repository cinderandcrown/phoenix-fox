// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Bundled (and remote-config-ready) model ids. Point at a newer cutting-edge model by
// updating model_catalog.json — or a future remote overlay — without an App Store rebuild
// of app logic. Defaults: Grok, latest vision-capable Grok 4.

import Foundation

struct ProviderModelCatalogFile: Equatable, Codable, Sendable {
    var version: Int
    var defaultProvider: AIProviderID
    /// Includes the synthetic `on_device` token as a string in JSON; parsed separately.
    var fallbackOrder: [String]
    var providers: [ProviderCatalogEntry]
}

struct ProviderCatalogEntry: Equatable, Codable, Sendable {
    enum APIStyle: String, Codable, Sendable {
        case openaiCompatible = "openai_compatible"
        case anthropicMessages = "anthropic_messages"
        case gemini
    }

    var id: AIProviderID
    var displayName: String
    var apiStyle: APIStyle
    var baseURL: String
    var supportsVision: Bool
    var supportsTools: Bool
    var supportsRealtimeVoice: Bool
    var supportsStreaming: Bool
    var models: RoleModels
    var modelChoices: [String]

    struct RoleModels: Equatable, Codable, Sendable {
        var instant: String
        var top: String
        var vision: String
    }

    var capabilities: AIProviderCapabilities {
        AIProviderCapabilities(
            supportsVision: supportsVision,
            supportsTools: supportsTools,
            supportsRealtimeVoice: supportsRealtimeVoice,
            supportsStreaming: supportsStreaming
        )
    }
}

/// Resolved catalog used at runtime.
struct ProviderModelCatalog: Equatable, Sendable {
    var version: Int
    var defaultProvider: AIProviderID
    /// Cloud providers first; `onDevice` means fall through to Apple Intelligence / local.
    var fallbackOrder: [FallbackStep]
    var providers: [AIProviderID: ProviderCatalogEntry]

    enum FallbackStep: Equatable, Sendable {
        case provider(AIProviderID)
        case onDevice

        var rawValue: String {
            switch self {
            case .provider(let id): return id.rawValue
            case .onDevice: return "on_device"
            }
        }

        static func parse(_ raw: String) -> FallbackStep? {
            if raw == "on_device" { return .onDevice }
            guard let id = AIProviderID(rawValue: raw) else { return nil }
            return .provider(id)
        }
    }

    func entry(for id: AIProviderID) -> ProviderCatalogEntry? { providers[id] }

    func model(for id: AIProviderID, role: ModelRole) -> String? {
        guard let models = providers[id]?.models else { return nil }
        switch role {
        case .instant: return models.instant
        case .top: return models.top
        case .vision: return models.vision
        }
    }

    /// Prefer Settings override when non-empty; else catalog role id.
    func resolvedModel(provider: AIProviderID, role: ModelRole, settings: AppSettings) -> String {
        let override: String = {
            switch provider {
            case .grok: return settings.grokModel
            case .openAI: return settings.openAIModel
            case .anthropic: return settings.claudeModel
            case .gemini: return ""
            }
        }()
        if !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        return model(for: provider, role: role) ?? ProviderModelCatalogStore.legacyDefault(for: provider)
    }
}

enum ProviderModelCatalogStore {
    /// Embedded copy of `Resources/model_catalog.json` so Linux tests and a missing bundle still work.
    static let embeddedJSON = """
    {"version":1,"defaultProvider":"grok","fallbackOrder":["grok","anthropic","openai","on_device"],"providers":[{"id":"grok","displayName":"Grok (xAI)","apiStyle":"openai_compatible","baseURL":"https://api.x.ai/v1","supportsVision":true,"supportsTools":true,"supportsRealtimeVoice":false,"supportsStreaming":true,"models":{"instant":"grok-4.20-non-reasoning","top":"grok-4","vision":"grok-4"},"modelChoices":["grok-4.20-non-reasoning","grok-4","grok-4-fast-non-reasoning","grok-3-mini"]},{"id":"openai","displayName":"ChatGPT (OpenAI)","apiStyle":"openai_compatible","baseURL":"https://api.openai.com/v1","supportsVision":true,"supportsTools":true,"supportsRealtimeVoice":true,"supportsStreaming":true,"models":{"instant":"gpt-4o-mini","top":"gpt-4o","vision":"gpt-4o"},"modelChoices":["gpt-4o-mini","gpt-4o","gpt-4.1-mini","gpt-4.1"]},{"id":"anthropic","displayName":"Claude (Anthropic)","apiStyle":"anthropic_messages","baseURL":"https://api.anthropic.com/v1","supportsVision":true,"supportsTools":true,"supportsRealtimeVoice":false,"supportsStreaming":true,"models":{"instant":"claude-haiku-4-5","top":"claude-sonnet-4-5","vision":"claude-sonnet-4-5"},"modelChoices":["claude-haiku-4-5","claude-sonnet-4-5","claude-opus-4-5"]},{"id":"gemini","displayName":"Gemini (Google)","apiStyle":"gemini","baseURL":"https://generativelanguage.googleapis.com/v1beta","supportsVision":true,"supportsTools":true,"supportsRealtimeVoice":true,"supportsStreaming":true,"models":{"instant":"gemini-2.0-flash","top":"gemini-2.5-pro","vision":"gemini-2.0-flash"},"modelChoices":["gemini-2.0-flash","gemini-2.5-pro"]}]}
    """

    /// Optional remote-config / test overlay. Cleared with `replaceForTesting(nil)`.
    private final class OverlayBox: @unchecked Sendable {
        let lock = NSLock()
        var value: ProviderModelCatalog?
    }
    private static let overlayBox = OverlayBox()

    static func load(bundle: Bundle = .main, overlayJSON: Data? = nil) -> ProviderModelCatalog {
        if let overlayJSON, let catalog = parse(overlayJSON) {
            replaceForTesting(catalog)
            return catalog
        }
        overlayBox.lock.lock()
        let existing = overlayBox.value
        overlayBox.lock.unlock()
        if let existing { return existing }
        if let url = bundle.url(forResource: "model_catalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let catalog = parse(data) {
            return catalog
        }
        return parse(Data(embeddedJSON.utf8))!
    }

    /// Tests and remote-config can replace the in-memory overlay.
    static func replaceForTesting(_ catalog: ProviderModelCatalog?) {
        overlayBox.lock.lock()
        overlayBox.value = catalog
        overlayBox.lock.unlock()
    }

    static func parse(_ data: Data) -> ProviderModelCatalog? {
        guard let file = try? JSONDecoder().decode(ProviderModelCatalogFile.self, from: data) else {
            return nil
        }
        var map: [AIProviderID: ProviderCatalogEntry] = [:]
        for entry in file.providers { map[entry.id] = entry }
        let order = file.fallbackOrder.compactMap(ProviderModelCatalog.FallbackStep.parse)
        return ProviderModelCatalog(
            version: file.version,
            defaultProvider: file.defaultProvider,
            fallbackOrder: order.isEmpty ? [.provider(.grok), .provider(.anthropic), .onDevice] : order,
            providers: map
        )
    }
}

extension ProviderModelCatalogStore {
    static func legacyDefault(for provider: AIProviderID) -> String {
        switch provider {
        case .grok: return "grok-4.20-non-reasoning"
        case .openAI: return "gpt-4o-mini"
        case .anthropic: return "claude-haiku-4-5"
        case .gemini: return "gemini-2.0-flash"
        }
    }

    /// Catalog-backed id for a voice backend. Settings override still wins when non-empty.
    static func modelID(for brain: AIBackendType, settings: AppSettings, role: ModelRole = .instant) -> String {
        if let provider = AIProviderID.from(backend: brain) {
            return load().resolvedModel(provider: provider, role: role, settings: settings)
        }
        return legacyDefault(for: .openAI)
    }
}
