// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Picks a provider for a turn and retries down the fallback chain on error / missing capability.
// App logic asks the router; it never names Grok/Claude/OpenAI except through AIProviderID.

import Foundation

struct ProviderRouter: Sendable {
    var policy: ProviderFallbackPolicy
    var catalog: ProviderModelCatalog
    var transport: AIHTTPTransport

    init(
        policy: ProviderFallbackPolicy = .catalogDefault,
        catalog: ProviderModelCatalog = ProviderModelCatalogStore.load(),
        transport: AIHTTPTransport = URLSessionAITransport()
    ) {
        self.policy = policy
        self.catalog = catalog
        self.transport = transport
    }

    struct Outcome: Equatable, Sendable {
        var provider: AIProviderID
        var model: String
        var reply: AIChatReply
        var attempted: [AIProviderID]
    }

    /// Completes via the first configured provider that can satisfy `need`, then fallbacks.
    func complete(
        text: String,
        imageJPEG: Data?,
        system: String?,
        need: TurnNeed,
        settings: AppSettings,
        onDeviceAvailable: Bool = false
    ) async throws -> Outcome {
        let role = TurnClassifier.role(for: need) ?? .instant
        var attempted: [AIProviderID] = []
        var failed: AIProviderID? = nil
        var lastError: Error = AIProviderError.notConfigured

        while let step = policy.next(
            after: failed,
            need: need,
            isConfigured: { settings.isProviderKeyConfigured($0) },
            onDeviceAvailable: onDeviceAvailable
        ) {
            switch step {
            case .onDevice:
                throw lastError
            case .provider(let id):
                if attempted.contains(id) {
                    failed = id
                    continue
                }
                attempted.append(id)
                let provider = AIProviderRegistry.provider(for: id)
                if imageJPEG != nil, !provider.capabilities.supportsVision {
                    failed = id
                    lastError = AIProviderError.missingCapability("accept images")
                    continue
                }
                let model = catalog.resolvedModel(provider: id, role: role, settings: settings)
                let key = Self.key(for: id, settings: settings)
                let request = AIChatRequest(
                    model: model,
                    messages: [AIChatMessage(role: "user", content: text)],
                    system: system,
                    imageJPEG: imageJPEG,
                    offerTools: false,
                    maxTokens: role == .instant ? 300 : 600,
                    apiKey: key
                )
                do {
                    let reply = try await provider.complete(request, transport: transport)
                    return Outcome(provider: id, model: model, reply: reply, attempted: attempted)
                } catch {
                    failed = id
                    lastError = error
                }
            }
        }
        throw lastError
    }

    static func key(for id: AIProviderID, settings: AppSettings) -> String {
        switch id {
        case .grok: return settings.grokAPIKey
        case .openAI: return settings.openAIAPIKey
        case .anthropic: return settings.claudeAPIKey
        case .gemini: return settings.geminiAPIKey
        }
    }
}
