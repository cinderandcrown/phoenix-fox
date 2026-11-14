// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Jarvis - BrainCatalog.swift
// One list of brains. Adding a provider is a case, a type that conforms to AIBackend,
// and one row here. The voice agent never names a vendor except through this catalog.
//
// "Your own assistant" is the relay protocol. xAI, Anthropic, OpenAI, Google, and
// on-device models are peers. A future assistant platform is another case.

import Foundation

extension AIBackendType {
    /// Brains that can answer a short turn in one HTTP call. Gemini Live is a stream, not one of these.
    static var instantChoices: [AIBackendType] { [.grok, .claude, .openAI] }
}

enum BrainCatalog {
    /// The extension point. Keep this switch as the only place a brain id becomes an object.
    @MainActor
    static func backend(for type: AIBackendType) -> AIBackend {
        switch type {
        case .openClaw: return OpenClawService.shared
        case .geminiLive: return GeminiLiveService.shared
        case .openAI: return OpenAIService.shared
        case .grok: return GrokService.shared
        case .claude: return ClaudeService.shared
        case .hermes: return HermesService.shared
        case .appleFoundation: return AppleFoundationService.shared
        case .localGemma: return GemmaLocalService.shared
        case .ownAssistant: return OwnAssistantService.shared
        }
    }
}

/// Cheap / role model ids for fast mode. Source of truth is `model_catalog.json`
/// (`ProviderModelCatalogStore`). Settings overrides still win when non-empty.
enum InstantModels {
    static var grok: String { ProviderModelCatalogStore.load().model(for: .grok, role: .instant) ?? "grok-4.20-non-reasoning" }
    static var claude: String { ProviderModelCatalogStore.load().model(for: .anthropic, role: .instant) ?? "claude-haiku-4-5" }
    static var openAI: String { ProviderModelCatalogStore.load().model(for: .openAI, role: .instant) ?? "gpt-4o-mini" }

    static func id(for brain: AIBackendType, settings: AppSettings, role: ModelRole = .instant) -> String {
        ProviderModelCatalogStore.modelID(for: brain, settings: settings, role: role)
    }
}
