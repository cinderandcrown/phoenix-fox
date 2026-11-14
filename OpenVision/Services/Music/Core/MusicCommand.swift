// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Voice → music intents. Pure parsing so Linux unit tests cover the grammar.

import Foundation

enum MusicCommand: Equatable, Sendable {
    case play(query: String?)
    case pause
    case resume
    case skip
    case previous
    case volumeUp
    case volumeDown
    case save
    case nowPlaying
    case identify
    /// "play my Discover Weekly" / playlist by name
    case playPlaylist(name: String)
}

enum MusicCommandParser {
    /// Parses a cleaned voice command. Nil when it is not a music request.
    static func parse(_ raw: String) -> MusicCommand? {
        let text = normalize(raw)
        guard !text.isEmpty else { return nil }

        if matches(text, ["what song is this", "what's this song", "whats this song", "who sings this", "name this song", "shazam"]) {
            return .identify
        }
        if matches(text, ["what song is playing", "what's playing", "whats playing", "what is playing", "now playing", "what's this track"]) {
            return .nowPlaying
        }
        if matches(text, ["skip", "next song", "next track", "skip this", "skip song"]) {
            return .skip
        }
        if matches(text, ["previous", "previous song", "last song", "go back", "previous track"]) {
            return .previous
        }
        if matches(text, ["pause", "pause music", "pause the music", "stop the music", "stop music"]) {
            // "stop" alone is reserved for TTS interrupt elsewhere.
            return .pause
        }
        if matches(text, ["resume", "resume music", "continue music", "unpause", "keep playing"]) {
            return .resume
        }
        if matches(text, ["save this song", "save this track", "save song", "love this song", "add to library", "save this"]) {
            return .save
        }
        if matches(text, ["turn it down", "volume down", "quieter", "turn down the music", "lower the volume"]) {
            return .volumeDown
        }
        if matches(text, ["turn it up", "volume up", "louder", "turn up the music", "raise the volume"]) {
            return .volumeUp
        }

        if let playlist = playlistName(in: text) {
            return .playPlaylist(name: playlist)
        }

        // Before the generic "play …" catch-all.
        if text.contains("play something chill") || text == "play chill" || text.hasPrefix("play chill ") {
            return .play(query: "chill")
        }
        if matches(text, ["play music", "start music", "play something"]) {
            return .play(query: nil)
        }
        if text.hasPrefix("play ") {
            let query = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if query.isEmpty || query == "music" || query == "something" {
                return .play(query: nil)
            }
            return .play(query: query)
        }

        return nil
    }

    private static func playlistName(in text: String) -> String? {
        let prefixes = ["play my ", "play the playlist ", "play playlist "]
        for prefix in prefixes where text.hasPrefix(prefix) {
            let name = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return nil
    }

    private static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != " " })
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text == $0 || text.hasPrefix($0 + " ") }
    }
}
