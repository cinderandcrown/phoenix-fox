// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class AIProviderTests: XCTestCase {

    // MARK: - Catalog

    func testBundledCatalogDefaultsToGrokVision() throws {
        ProviderModelCatalogStore.replaceForTesting(nil)
        let catalog = ProviderModelCatalogStore.load()
        XCTAssertEqual(catalog.defaultProvider, .grok)
        XCTAssertEqual(catalog.model(for: .grok, role: .vision), "grok-4")
        XCTAssertEqual(catalog.model(for: .grok, role: .instant), "grok-4.20-non-reasoning")
        XCTAssertEqual(catalog.fallbackOrder.first, .provider(.grok))
        XCTAssertTrue(catalog.fallbackOrder.contains(.onDevice))
    }

    func testCatalogParseRejectsGarbage() {
        XCTAssertNil(ProviderModelCatalogStore.parse(Data("not-json".utf8)))
    }

    func testSettingsOverrideWinsOverCatalog() {
        ProviderModelCatalogStore.replaceForTesting(nil)
        var settings = AppSettings()
        settings.grokModel = "grok-custom-test"
        let model = ProviderModelCatalogStore.load()
            .resolvedModel(provider: .grok, role: .vision, settings: settings)
        XCTAssertEqual(model, "grok-custom-test")
    }

    // MARK: - OpenAI-compatible adapter (mocked HTTP)

    func testGrokCompatibleParsesChatCompletions() throws {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"Hello from Grok"}}],"usage":{"prompt_tokens":3,"completion_tokens":4}}
        """
        let reply = try OpenAICompatibleProvider.parseChatCompletions(Data(json.utf8))
        XCTAssertEqual(reply.text, "Hello from Grok")
        XCTAssertEqual(reply.inputTokens, 3)
        XCTAssertEqual(reply.outputTokens, 4)
    }

    func testOpenAICompatibleTestKeySucceedsOn200() async throws {
        let transport = MockAITransport { request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (Data(#"{"data":[]}"#.utf8), response)
        }
        let provider = OpenAICompatibleProvider(
            id: .grok,
            baseURL: "https://api.x.ai/v1",
            capabilities: AIProviderCapabilities(
                supportsVision: true, supportsTools: true,
                supportsRealtimeVoice: false, supportsStreaming: true
            )
        )
        try await provider.testKey("test-key", transport: transport)
    }

    func testOpenAICompatibleTestKeyFailsOn401() async {
        let transport = MockAITransport { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (Data(#"{"error":{"message":"bad key"}}"#.utf8), response)
        }
        let provider = AIProviderRegistry.provider(for: .openAI)
        do {
            try await provider.testKey("nope", transport: transport)
            XCTFail("expected failure")
        } catch let error as AIProviderError {
            guard case .http(let status, _) = error else {
                return XCTFail("wrong error \(error)")
            }
            XCTAssertEqual(status, 401)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testRedactSecretsStripsKeyMaterial() {
        let raw = "Invalid sk-abc123XYZ999 and xai-deadbeef01 tokens"
        let clean = OpenAICompatibleProvider.redactSecrets(raw)
        XCTAssertFalse(clean.contains("sk-abc"))
        XCTAssertFalse(clean.contains("xai-dead"))
        XCTAssertTrue(clean.contains("[redacted]"))
    }

    // MARK: - Anthropic adapter

    func testAnthropicParsesMessages() throws {
        let json = """
        {"content":[{"type":"text","text":"Hi from Claude"}],"usage":{"input_tokens":2,"output_tokens":5}}
        """
        let reply = try AnthropicProvider.parseMessages(Data(json.utf8))
        XCTAssertEqual(reply.text, "Hi from Claude")
        XCTAssertEqual(reply.inputTokens, 2)
        XCTAssertEqual(reply.outputTokens, 5)
    }

    func testAnthropicCompleteUsesMessagesEndpoint() async throws {
        let transport = MockAITransport { request in
            XCTAssertEqual(request.url?.path, "/v1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "ant-key")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "anthropic-version"))
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            XCTAssertEqual(body?["model"] as? String, "claude-haiku-4-5")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let data = Data(#"{"content":[{"type":"text","text":"ok"}]}"#.utf8)
            return (data, response)
        }
        let reply = try await AnthropicProvider().complete(
            AIChatRequest(
                model: "claude-haiku-4-5",
                messages: [AIChatMessage(role: "user", content: "hi")],
                system: "You are Phoenix.",
                imageJPEG: nil,
                offerTools: false,
                maxTokens: 32,
                apiKey: "ant-key"
            ),
            transport: transport
        )
        XCTAssertEqual(reply.text, "ok")
    }

    // MARK: - Fallback

    func testFallbackSkipsUnconfiguredThenPicksClaude() {
        let policy = ProviderFallbackPolicy(order: [
            .provider(.grok), .provider(.anthropic), .onDevice,
        ])
        let step = policy.primary(
            need: .instant,
            isConfigured: { $0 == .anthropic },
            onDeviceAvailable: false
        )
        XCTAssertEqual(step, .provider(.anthropic))
    }

    func testFallbackAfterGrokFailureGoesToClaude() {
        let policy = ProviderFallbackPolicy(order: [
            .provider(.grok), .provider(.anthropic), .onDevice,
        ])
        let step = policy.next(
            after: .grok,
            need: .vision,
            isConfigured: { $0 == .grok || $0 == .anthropic },
            onDeviceAvailable: false
        )
        XCTAssertEqual(step, .provider(.anthropic))
    }

    func testRouterTriesFallbackOnHTTPError() async throws {
        final class Counter: @unchecked Sendable {
            var hits = 0
        }
        let counter = Counter()
        let transport = MockAITransport { request in
            counter.hits += 1
            if counter.hits == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
                )!
                return (Data(#"{"error":{"message":"boom"}}"#.utf8), response)
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let data = Data(#"{"content":[{"type":"text","text":"claude saved it"}]}"#.utf8)
            return (data, response)
        }
        var settings = AppSettings()
        settings.grokAPIKey = "g"
        settings.claudeAPIKey = "c"
        settings.providerFallbackOrder = ["grok", "anthropic"]
        let router = ProviderRouter(
            policy: settings.resolvedProviderFallback,
            catalog: ProviderModelCatalogStore.load(),
            transport: transport
        )
        let outcome = try await router.complete(
            text: "hello",
            imageJPEG: nil,
            system: nil,
            need: .instant,
            settings: settings
        )
        XCTAssertEqual(outcome.provider, .anthropic)
        XCTAssertEqual(outcome.reply.text, "claude saved it")
        XCTAssertEqual(outcome.attempted, [.grok, .anthropic])
    }

    // MARK: - Registry / capabilities

    func testRegistryGrokIsOpenAICompatibleAtXAI() {
        let grok = AIProviderRegistry.provider(for: .grok)
        XCTAssertEqual(grok.id, .grok)
        XCTAssertEqual(grok.defaultBaseURL, "https://api.x.ai/v1")
        XCTAssertTrue(grok.capabilities.supportsVision)
        XCTAssertTrue(grok.capabilities.supportsTools)
        XCTAssertFalse(grok.capabilities.supportsRealtimeVoice)
    }

    func testProviderIDMapsToBackendAndKeychainAccount() {
        XCTAssertEqual(AIProviderID.grok.backendType, .grok)
        XCTAssertEqual(AIProviderID.anthropic.backendType, .claude)
        XCTAssertEqual(AIProviderID.grok.keychainAccount, "grokAPIKey")
        XCTAssertEqual(AIProviderID.from(backend: .claude), .anthropic)
        XCTAssertNil(AIProviderID.from(backend: .ownAssistant))
    }
}

// MARK: - Mock transport

struct MockAITransport: AIHTTPTransport {
    let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request)
    }
}
