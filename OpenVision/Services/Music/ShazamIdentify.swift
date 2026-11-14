// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import AVFoundation
import Foundation
import ShazamKit

/// On-device song ID via ShazamKit (bonus for "what song is this").
@MainActor
final class ShazamIdentify: NSObject {
    static let shared = ShazamIdentify()

    private let session = SHSession()
    private var engine: AVAudioEngine?
    private var continuation: CheckedContinuation<NowPlayingInfo, Error>?
    private var timeoutTask: Task<Void, Never>?

    func identify(timeoutSeconds: Double = 8) async throws -> NowPlayingInfo {
        if continuation != nil {
            throw MusicProviderError.unavailable("I'm already listening for a song.")
        }
        session.delegate = self
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, time in
            self?.session.matchStreamingBuffer(buffer, at: time)
        }
        try engine.start()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<NowPlayingInfo, Error>) in
            self.continuation = cont
            self.timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                guard !Task.isCancelled else { return }
                self.finish(with: .failure(MusicProviderError.unavailable("I couldn't identify that song.")))
            }
        }
    }

    private func finish(with result: Result<NowPlayingInfo, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }
}

extension ShazamIdentify: SHSessionDelegate {
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        let info = NowPlayingInfo(
            title: item.title ?? "Unknown",
            artist: item.artist ?? "",
            album: nil,
            uri: item.appleMusicID
        )
        Task { @MainActor in
            self.finish(with: .success(info))
        }
    }

    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        Task { @MainActor in
            self.finish(with: .failure(error ?? MusicProviderError.unavailable("I couldn't identify that song.")))
        }
    }
}
