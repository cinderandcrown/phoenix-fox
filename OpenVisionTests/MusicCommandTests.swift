// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class MusicCommandTests: XCTestCase {
    func testPlayPlaylist() {
        XCTAssertEqual(
            MusicCommandParser.parse("play my Discover Weekly"),
            .playPlaylist(name: "discover weekly")
        )
    }

    func testSkipPauseSaveIdentify() {
        XCTAssertEqual(MusicCommandParser.parse("skip"), .skip)
        XCTAssertEqual(MusicCommandParser.parse("pause the music"), .pause)
        XCTAssertEqual(MusicCommandParser.parse("save this song"), .save)
        XCTAssertEqual(MusicCommandParser.parse("what song is this"), .identify)
        XCTAssertEqual(MusicCommandParser.parse("what's playing"), .nowPlaying)
        XCTAssertEqual(MusicCommandParser.parse("turn it down"), .volumeDown)
    }

    func testPlayQuery() {
        XCTAssertEqual(MusicCommandParser.parse("play something chill"), .play(query: "chill"))
        XCTAssertEqual(MusicCommandParser.parse("play Bohemian Rhapsody"), .play(query: "bohemian rhapsody"))
    }

    func testNonMusicIsNil() {
        XCTAssertNil(MusicCommandParser.parse("what time is it"))
        XCTAssertNil(MusicCommandParser.parse("ask Indy about the gate"))
    }
}

final class MusicSessionPolicyTests: XCTestCase {
    func testMusicUsesA2DP() {
        XCTAssertEqual(MusicSessionPolicy.link(for: .musicA2DP, glassesPresent: true), .a2dpPlayback)
        let flags = MusicSessionPolicy.routeFlags(phase: .musicA2DP)
        XCTAssertFalse(flags.listening)
        XCTAssertTrue(flags.longPlayback)
    }

    func testVoiceCaptureUsesHFPThenRestoresMusic() {
        XCTAssertEqual(MusicSessionPolicy.link(for: .voiceCaptureHFP, glassesPresent: true), .hfpConversation)
        XCTAssertTrue(MusicSessionPolicy.shouldDuckOthers(phase: .voiceCaptureHFP))
        XCTAssertEqual(MusicSessionPolicy.phaseAfterCommand(musicWasPlaying: true), .musicA2DP)
        XCTAssertEqual(MusicSessionPolicy.phaseAfterCommand(musicWasPlaying: false), .idle)
    }

    func testNeverClaimsBothLinks() {
        for phase in [MusicAudioPhase.musicA2DP, .voiceCaptureHFP, .assistantDucked] {
            let link = MusicSessionPolicy.link(for: phase, glassesPresent: true)
            XCTAssertFalse(link.allowsHFP && link.allowsA2DP, "\(phase) must not allow HFP and A2DP together")
        }
    }
}
