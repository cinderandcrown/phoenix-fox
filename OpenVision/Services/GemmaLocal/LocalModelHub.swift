// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// On-device model download without the MLXHuggingFace compiler macros.
// Those macros pull SwiftSyntax, and the SwiftPM prebuilt of SwiftCompilerPlugin
// has no iOS simulator slice, so the simulator build never got past them.
// This is the same bridge the macros would have expanded to: HubClient as a
// Downloader, AutoTokenizer as a TokenizerLoader.

import Foundation
import HuggingFace
import MLXLMCommon
import Tokenizers

enum LocalModelHubError: LocalizedError {
    case invalidRepositoryID(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let id):
            return "Invalid Hugging Face repository id '\(id)'. Expected namespace/name."
        }
    }
}

enum LocalModelHub {
    static func downloader() -> any MLXLMCommon.Downloader {
        HubDownloader(client: HubClient())
    }

    static func tokenizerLoader() -> any MLXLMCommon.TokenizerLoader {
        TransformersTokenizerLoader()
    }
}

private struct HubDownloader: MLXLMCommon.Downloader {
    let client: HubClient

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repo = Repo.ID(rawValue: id) else {
            throw LocalModelHubError.invalidRepositoryID(id)
        }
        // `useLatest` is part of the MLX downloader contract. HubClient already
        // reuses a snapshot when the files are present; a fresh connect does not
        // re-download multi-gigabyte weights on every launch.
        _ = useLatest
        return try await client.downloadSnapshot(
            of: repo,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: { @MainActor progress in
                progressHandler(progress)
            }
        )
    }
}

private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
