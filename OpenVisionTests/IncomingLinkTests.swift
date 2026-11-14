// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class IncomingLinkTests: XCTestCase {

    private func link(_ text: String) -> IncomingLink? {
        URL(string: text).flatMap(IncomingLink.init)
    }

    func testMetaCallbackGoesToTheGlassesSDK() throws {
        let text = "https://phoenix-fox-links.cinderandcrown.workers.dev/dat?metaWearablesAction=register&code=abc"
        XCTAssertEqual(link(text), .wearables(try XCTUnwrap(URL(string: text))))
        XCTAssertNotNil(link("https://phoenix-fox-links.cinderandcrown.workers.dev/dat"))
        XCTAssertNotNil(link("https://phoenix-fox-links.cinderandcrown.workers.dev/dat/callback"))
    }

    func testHostAndSchemeMatchWithoutRegardToCase() {
        XCTAssertNotNil(link("HTTPS://Phoenix-Fox-Links.CinderAndCrown.workers.dev/dat"))
    }

    func testAppPathsAreRecognised() {
        XCTAssertEqual(link("https://phoenix-fox-links.cinderandcrown.workers.dev/app/settings"), .app(path: "/app/settings"))
    }

    func testOtherHostsAreRejected() {
        XCTAssertNil(link("https://evil.example/dat?metaWearablesAction=register"))
        XCTAssertNil(link("https://phoenix-fox-links.cinderandcrown.workers.dev.evil.example/dat"))
        XCTAssertNil(link("https://cinderandcrown.workers.dev/dat"))
    }

    func testOtherSchemesAreRejected() {
        XCTAssertNil(link("http://phoenix-fox-links.cinderandcrown.workers.dev/dat"))
        XCTAssertNil(link("phoenixfox://dat"))
        XCTAssertNil(link("phoenixfox://phoenix-fox-links.cinderandcrown.workers.dev/dat"))
    }

    func testPathsOutsideTheAssociationFileAreRejected() {
        XCTAssertNil(link("https://phoenix-fox-links.cinderandcrown.workers.dev/"))
        XCTAssertNil(link("https://phoenix-fox-links.cinderandcrown.workers.dev/other"))
        XCTAssertNil(link("https://phoenix-fox-links.cinderandcrown.workers.dev/.well-known/apple-app-site-association"))
    }

    func testTheBundledConfigurationNamesTheSameLink() throws {
        // The Info.plist value, the entitlement, and this type must agree, or Meta AI
        // returns to a link the app does not accept.
        let mwdat = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "MWDAT") as? [String: Any])
        let configured = try XCTUnwrap(mwdat["AppLinkURLScheme"] as? String)
        XCTAssertEqual(configured, "https://\(IncomingLink.host)/dat")
        XCTAssertNotNil(link(configured))
        XCTAssertEqual(mwdat["MetaAppID"] as? String, "1651172483404286")
    }
}
