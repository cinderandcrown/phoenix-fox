// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class PushRegistrationTests: XCTestCase {
    private let relay = RelayEndpoint(address: "https://relay.example", token: "one")

    func testNothingIsSentBeforeAppleGivesAToken() {
        XCTAssertNil(PushRegistration().pending(for: relay))
    }

    func testATokenThatArrivesBeforeTheRelayIsSavedWaitsForIt() throws {
        var push = PushRegistration()
        push.received(token: "abc")
        XCTAssertNil(push.pending(for: nil))

        let send = try XCTUnwrap(push.pending(for: relay))
        XCTAssertEqual(send.token, "abc")
        XCTAssertEqual(send.endpoint, relay)
    }

    func testAnAcceptedTokenIsNotSentAgain() throws {
        var push = PushRegistration()
        push.received(token: "abc")
        push.accepted(try XCTUnwrap(push.pending(for: relay)))
        XCTAssertNil(push.pending(for: relay))

        push.received(token: "abc")
        XCTAssertNil(push.pending(for: relay))
    }

    func testASendThatFailedIsStillPending() {
        var push = PushRegistration()
        push.received(token: "abc")
        _ = push.pending(for: relay)
        XCTAssertNotNil(push.pending(for: relay))
    }

    func testANewTokenIsSent() throws {
        var push = PushRegistration()
        push.received(token: "abc")
        push.accepted(try XCTUnwrap(push.pending(for: relay)))

        push.received(token: "def")
        XCTAssertEqual(push.pending(for: relay)?.token, "def")
    }

    func testAChangedRelayOrRelayTokenGetsTheToken() throws {
        var push = PushRegistration()
        push.received(token: "abc")
        push.accepted(try XCTUnwrap(push.pending(for: relay)))

        XCTAssertNotNil(push.pending(for: RelayEndpoint(address: "https://other.example", token: "one")))
        XCTAssertNotNil(push.pending(for: RelayEndpoint(address: "https://relay.example", token: "two")))
    }
}
