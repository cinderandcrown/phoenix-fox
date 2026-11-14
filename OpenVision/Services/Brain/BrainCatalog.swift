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

/// Cheap model ids for fast mode. Override in Settings. These are voice defaults, not a
/// commitment that a vendor will keep the alias. Empty settings fall back to these.
enum InstantModels {
    static let grok = "grok-4-fast-non-reasoning"
    static let claude = "claude-haiku-4-5"
    static let openAI = "gpt-4o-mini"

    static func id(for brain: AIBackendType, settings: AppSettings) -> String {
        switch brain {
        case .grok:
            return settings.grokModel.isEmpty ? grok : settings.grokModel
        case .claude:
            return settings.claudeModel.isEmpty ? claude : settings.claudeModel
        case .openAI:
            return settings.openAIModel.isEmpty ? openAI : settings.openAIModel
        default:
            return openAI
        }
    }
}
