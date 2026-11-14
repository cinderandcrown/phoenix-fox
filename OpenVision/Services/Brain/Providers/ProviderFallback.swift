// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Configurable fallback: e.g. Grok → Claude → on-device when a provider errors or lacks a capability.

import Foundation

struct ProviderFallbackPolicy: Equatable, Sendable {
    var order: [ProviderModelCatalog.FallbackStep]

    static var catalogDefault: ProviderFallbackPolicy {
        ProviderFallbackPolicy(order: ProviderModelCatalogStore.load().fallbackOrder)
    }

    /// Next step after `failed` that is configured and meets `need`.
    func next(
        after failed: AIProviderID?,
        need: TurnNeed,
        isConfigured: (AIProviderID) -> Bool,
        onDeviceAvailable: Bool
    ) -> ProviderModelCatalog.FallbackStep? {
        let role = TurnClassifier.role(for: need)
        var passedFailure = failed == nil
        for step in order {
            if !passedFailure {
                if case .provider(let id) = step, id == failed {
                    passedFailure = true
                }
                continue
            }
            switch step {
            case .onDevice:
                if need == .vision && !onDeviceAvailable { continue }
                if onDeviceAvailable || need == .local || need == .instant {
                    return .onDevice
                }
            case .provider(let id):
                guard isConfigured(id) else { continue }
                let caps = AIProviderRegistry.provider(for: id).capabilities
                if need == .vision, !caps.supportsVision { continue }
                if role == .top || role == .vision || role == .instant {
                    return .provider(id)
                }
            }
        }
        return nil
    }

    /// First configured provider that can handle the need.
    func primary(
        need: TurnNeed,
        isConfigured: (AIProviderID) -> Bool,
        onDeviceAvailable: Bool
    ) -> ProviderModelCatalog.FallbackStep? {
        next(after: nil, need: need, isConfigured: isConfigured, onDeviceAvailable: onDeviceAvailable)
    }
}

extension AppSettings {
    /// Fallback chain from settings when non-empty; else the bundled catalog.
    var resolvedProviderFallback: ProviderFallbackPolicy {
        let parsed = providerFallbackOrder.compactMap(ProviderModelCatalog.FallbackStep.parse)
        if parsed.isEmpty { return .catalogDefault }
        return ProviderFallbackPolicy(order: parsed)
    }

    func isProviderKeyConfigured(_ id: AIProviderID) -> Bool {
        switch id {
        case .grok: return isGrokConfigured
        case .openAI: return isOpenAIAPIAvailable
        case .anthropic: return isClaudeConfigured
        case .gemini: return isGeminiConfigured
        }
    }
}
