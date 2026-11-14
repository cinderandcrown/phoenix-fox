// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
#if canImport(UserNotifications)
import UserNotifications
#endif
@testable import PhoenixFox
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A relay that answers from a script and keeps every request it was sent.
private final class ScriptedRelay: RelayTransport, @unchecked Sendable {
    enum Step {
        case json(Int, String, headers: [String: String] = [:])
        case fail(URLError.Code)
    }

    private let lock = NSLock()
    private var steps: [Step]
    private var seen: [URLRequest] = []
    /// Called after each request, so a test can move its clock.
    var afterEach: (@Sendable () -> Void)?

    init(_ steps: [Step]) {
        self.steps = steps
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let step: Step? = {
            lock.lock()
            defer { lock.unlock() }
            seen.append(request)
            return steps.isEmpty ? nil : steps.removeFirst()
        }()
        afterEach?()
        switch step {
        case .json(let status, let body, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (Data(body.utf8), response)
        case .fail(let code):
            throw URLError(code)
        case nil:
            throw URLError(.badServerResponse)
        }
    }
}

/// A clock the test moves. Sleeping advances it instead of waiting.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    private var naps: [Duration] = []

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    var slept: [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return naps
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current.addTimeInterval(seconds)
        lock.unlock()
    }

    func sleep(_ duration: Duration) {
        lock.lock()
        naps.append(duration)
        current.addTimeInterval(TimeInterval(duration.components.seconds))
        lock.unlock()
    }
}

final class RelayClientTests: XCTestCase {

    private let endpoint = RelayEndpoint(address: "https://relay.test", token: "owner-token")!

    private func client(_ relay: ScriptedRelay, clock: TestClock = TestClock()) -> RelayClient {
        RelayClient(
            transport: relay,
            sleep: { clock.sleep($0) },
            now: { clock.now }
        )
    }

    private func ask(images: [Data] = []) -> RelayAsk {
        RelayAsk(
            id: "ask-1",
            text: "book a table",
            transcript: "Jarvis, book a table",
            timestamp: "2026-11-14T12:00:00Z",
            intent: "message",
            targetBot: "Indy",
            context: [.init(role: "user", text: "hello")],
            replyTo: nil,
            images: images
        )
    }

    private func body(_ request: URLRequest) throws -> [String: JSONValue] {
        let data = try XCTUnwrap(request.httpBody)
        return [String: JSONValue](jsonObject: try JSONSerialization.jsonObject(with: data))
    }

    // MARK: Requests

    func testEveryRequestCarriesTheBearerAndANamedAgent() async throws {
        let relay = ScriptedRelay([
            .json(202, #"{"id":"ask-1","status":"pending","delivery":"webhook"}"#),
            .json(200, #"{"id":"ask-1","status":"ready","text":"Done.","from_bot":"Indy","replies":[{"text":"Done.","from_bot":"Indy"}],"done":true}"#),
        ])
        _ = try await client(relay).ask(ask(), to: endpoint)

        XCTAssertEqual(relay.requests.count, 2)
        for request in relay.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owner-token")
            let agent = try XCTUnwrap(request.value(forHTTPHeaderField: "User-Agent"))
            XCTAssertTrue(agent.hasPrefix("PhoenixFox/"), agent)
            XCTAssertFalse(agent.contains("CFNetwork"), agent)
        }
        XCTAssertEqual(relay.requests[0].httpMethod, "POST")
        XCTAssertEqual(relay.requests[0].url?.absoluteString, "https://relay.test/ask")
        XCTAssertEqual(relay.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(relay.requests[1].httpMethod, "GET")
        XCTAssertEqual(relay.requests[1].url?.absoluteString, "https://relay.test/reply/ask-1?wait=20")
    }

    func testAskBodyMatchesTheContract() async throws {
        let relay = ScriptedRelay([
            .json(202, #"{"id":"ask-1","status":"pending"}"#),
            .json(200, #"{"status":"ready","replies":[{"text":"Done.","from_bot":"Indy"}]}"#),
        ])
        var sent = ask(images: [Data([1, 2, 3]), Data([4, 5]), Data([6])])
        sent.replyTo = "inbox-9"
        _ = try await client(relay).ask(sent, to: endpoint)

        let json = try body(relay.requests[0])
        XCTAssertEqual(json["id"], "ask-1")
        XCTAssertEqual(json["text"], "book a table")
        XCTAssertEqual(json["transcript"], "Jarvis, book a table")
        XCTAssertEqual(json["timestamp"], "2026-11-14T12:00:00Z")
        XCTAssertEqual(json["intent"], "message")
        XCTAssertEqual(json["target_bot"], "Indy")
        XCTAssertEqual(json["reply_to"], "inbox-9")
        XCTAssertEqual(json["context"], [["role": "user", "text": "hello"]])
        // The first photo is `image`. `images` holds only the others, so nothing is sent twice.
        XCTAssertEqual(json["image"], "AQID")
        XCTAssertEqual(json["images"], ["BAU=", "Bg=="])
    }

    func testAskWithoutPhotosOrThreadOmitsThoseKeys() async throws {
        let relay = ScriptedRelay([
            .json(202, "{}"),
            .json(200, #"{"status":"ready","text":"Done.","from_bot":"Indy"}"#),
        ])
        _ = try await client(relay).ask(ask(), to: endpoint)
        let json = try body(relay.requests[0])
        XCTAssertNil(json["image"])
        XCTAssertNil(json["images"])
        XCTAssertNil(json["reply_to"])
    }

    // MARK: Replies

    func testOneReplyPerBot() async throws {
        let relay = ScriptedRelay([
            .json(202, "{}"),
            .json(200, #"{"status":"ready","text":"Clear. On it.","from_bot":"Fire Fox","replies":[{"text":"Clear.","from_bot":"Fire Fox"},{"text":"On it.","from_bot":"Indy"},{"text":"","from_bot":"Rally"}]}"#),
        ])
        let replies = try await client(relay).ask(ask(), to: endpoint)
        XCTAssertEqual(replies, [RelayReply(text: "Clear.", fromBot: "Fire Fox"), RelayReply(text: "On it.", fromBot: "Indy")])
    }

    func testFallsBackToTheJoinedTextWhenThereAreNoParts() async throws {
        let relay = ScriptedRelay([
            .json(202, "{}"),
            .json(200, #"{"status":"ready","text":"Booked for seven.","from_bot":"Indy"}"#),
        ])
        let replies = try await client(relay).ask(ask(), to: endpoint)
        XCTAssertEqual(replies, [RelayReply(text: "Booked for seven.", fromBot: "Indy")])
    }

    func testKeepsPollingWhileTheAskIsPending() async throws {
        let relay = ScriptedRelay([
            .json(202, "{}"),
            .json(200, #"{"id":"ask-1","status":"pending"}"#),
            .json(200, #"{"id":"ask-1","status":"pending"}"#),
            .json(200, #"{"status":"ready","text":"Done.","from_bot":"Indy"}"#),
        ])
        let clock = TestClock()
        // Each poll is held open by the relay for twenty seconds.
        relay.afterEach = { clock.advance(20) }
        let replies = try await client(relay, clock: clock).ask(ask(), to: endpoint)
        XCTAssertEqual(replies.map(\.text), ["Done."])
        XCTAssertEqual(relay.requests.count, 4)
        XCTAssertEqual(clock.slept, [])
    }

    func testDoesNotSpinWhenPendingComesBackAtOnce() async throws {
        let relay = ScriptedRelay([
            .json(202, "{}"),
            .json(200, #"{"status":"pending"}"#),
            .json(200, #"{"status":"ready","text":"Done.","from_bot":"Indy"}"#),
        ])
        let clock = TestClock()
        _ = try await client(relay, clock: clock).ask(ask(), to: endpoint)
        XCTAssertEqual(clock.slept, [.seconds(1)])
    }

    func testGivesUpAfterNinetySeconds() async throws {
        let relay = ScriptedRelay([.json(202, "{}")] + Array(repeating: .json(200, #"{"status":"pending"}"#), count: 10))
        let clock = TestClock()
        relay.afterEach = { clock.advance(20) }
        do {
            _ = try await client(relay, clock: clock).ask(ask(), to: endpoint)
            XCTFail("expected no reply")
        } catch {
            XCTAssertEqual(error as? RelayError, .noReply)
        }
        // One ask, then polls at 20, 40, 60, and 80 seconds. At 100 the deadline has passed.
        XCTAssertEqual(relay.requests.count, 5)
    }

    // MARK: Failures

    func testResendsTheSameAskAfterADroppedConnection() async throws {
        let relay = ScriptedRelay([
            .fail(.networkConnectionLost),
            .json(503, "{}"),
            .json(200, #"{"id":"ask-1","status":"pending"}"#),
            .json(200, #"{"status":"ready","text":"Done.","from_bot":"Indy"}"#),
        ])
        let clock = TestClock()
        let replies = try await client(relay, clock: clock).ask(ask(), to: endpoint)
        XCTAssertEqual(replies.map(\.text), ["Done."])
        let posts = relay.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(posts.count, 3)
        XCTAssertEqual(Set(try posts.map { try body($0)["id"] }), ["ask-1"])
        XCTAssertEqual(clock.slept, [.seconds(1), .seconds(2)])
    }

    func testStopsResendingAfterThreeAttempts() async throws {
        let relay = ScriptedRelay([.fail(.notConnectedToInternet), .fail(.notConnectedToInternet), .fail(.notConnectedToInternet)])
        do {
            _ = try await client(relay).ask(ask(), to: endpoint)
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? RelayError, .offline)
        }
        XCTAssertEqual(relay.requests.count, 3)
    }

    func testAPollThatFailsIsRetriedBecauseTheBotMayBeWorking() async throws {
        let relay = ScriptedRelay([
            .json(202, "{}"),
            .fail(.timedOut),
            .json(502, "{}"),
            .json(200, #"{"status":"ready","text":"Done.","from_bot":"Indy"}"#),
        ])
        let replies = try await client(relay).ask(ask(), to: endpoint)
        XCTAssertEqual(replies.map(\.text), ["Done."])
        XCTAssertEqual(relay.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    func testAWrongTokenIsNotRetried() async throws {
        let relay = ScriptedRelay([.json(401, #"{"error":"unauthorized"}"#)])
        do {
            _ = try await client(relay).ask(ask(), to: endpoint)
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? RelayError, .unauthorized)
        }
        XCTAssertEqual(relay.requests.count, 1)
    }

    func testStatusCodesBecomeErrorsTheWearerCanAct() {
        XCTAssertEqual(RelayError(status: 401, retryAfter: nil), .unauthorized)
        XCTAssertEqual(RelayError(status: 403, retryAfter: nil), .blocked)
        XCTAssertEqual(RelayError(status: 413, retryAfter: nil), .tooLarge)
        XCTAssertEqual(RelayError(status: 429, retryAfter: "17"), .rateLimited(retryAfter: 17))
        XCTAssertEqual(RelayError(status: 429, retryAfter: nil), .rateLimited(retryAfter: 60))
        XCTAssertEqual(RelayError(status: 500, retryAfter: nil), .server(status: 500))
        XCTAssertEqual(RelayError(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(RelayError(URLError(.cannotFindHost)), .offline)
        XCTAssertTrue(RelayError.offline.isTemporary)
        XCTAssertTrue(RelayError.server(status: 503).isTemporary)
        XCTAssertFalse(RelayError.server(status: 404).isTemporary)
        XCTAssertFalse(RelayError.unauthorized.isTemporary)
        XCTAssertFalse(RelayError.rateLimited(retryAfter: 60).isTemporary)
    }

    func testEveryErrorHasASentenceToSpeak() {
        let all: [RelayError] = [
            .notConfigured, .unauthorized, .blocked, .rateLimited(retryAfter: 60), .tooLarge,
            .server(status: 500), .server(status: 0), .offline, .noReply,
            .noBotConnected(wanted: nil), .noBotConnected(wanted: "Indy"), .malformed,
        ]
        for error in all {
            let line = error.localizedDescription
            XCTAssertTrue(line.hasSuffix("."), line)
            XCTAssertFalse(line.contains("RelayError"), line)
        }
    }

    func testACancelledRequestIsCancellationNotAnError() async {
        let relay = ScriptedRelay([.fail(.cancelled)])
        do {
            _ = try await client(relay).ask(ask(), to: endpoint)
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    func testAnswersThatAreNotJSONAreReportedAsUnreadable() async {
        let relay = ScriptedRelay([.json(202, "{}"), .json(200, "<html>captive portal</html>")])
        do {
            _ = try await client(relay).ask(ask(), to: endpoint)
            XCTFail("expected malformed")
        } catch {
            XCTAssertEqual(error as? RelayError, .malformed)
        }
    }

    // MARK: Inbox, device, health

    func testInboxDecodesMessagesAndToleratesMissingFields() async throws {
        let relay = ScriptedRelay([
            .json(200, #"{"messages":[{"id":"m1","text":"Gate is open","from_bot":"Driver","priority":"urgent"},{"id":"m2","text":"Later","from_bot":"Rally","priority":"someday"},{"id":"m3","text":""},{"text":"No id"}]}"#),
        ])
        let messages = try await client(relay).inbox(from: endpoint)
        XCTAssertEqual(relay.requests[0].url?.absoluteString, "https://relay.test/inbox?wait=25")
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0], RelayPush(id: "m1", text: "Gate is open", fromBot: "Driver", priority: .urgent))
        XCTAssertEqual(messages[1].priority, .normal)
        XCTAssertEqual(messages[2].text, "No id")
        XCTAssertFalse(messages[2].id.isEmpty)
    }

    func testAnEmptyInboxIsNotAnError() async throws {
        let relay = ScriptedRelay([.json(200, #"{"messages":[]}"#), .json(200, "{}")])
        let first = try await client(relay).inbox(from: endpoint)
        let second = try await client(relay).inbox(from: endpoint)
        XCTAssertEqual(first, [])
        XCTAssertEqual(second, [])
    }

    func testDeviceRegistrationNamesThePushService() async throws {
        let relay = ScriptedRelay([.json(200, #"{"status":"registered","devices":1}"#)])
        try await client(relay).registerDevice(token: "abcd", environment: .production, with: endpoint)
        XCTAssertEqual(relay.requests[0].url?.absoluteString, "https://relay.test/device")
        XCTAssertEqual(try body(relay.requests[0]), ["token": "abcd", "platform": "ios", "environment": "production"])
    }

    func testHealthReportsWhatTheRelaySays() async throws {
        let relay = ScriptedRelay([
            .json(200, #"{"ok":true,"apns":true,"devices":1,"webhooks":["Indy"],"webhook_problems":["Driver: url must be https"]}"#),
        ])
        let health = try await client(relay).health(of: endpoint)
        XCTAssertEqual(health, RelayHealth(ok: true, apns: true, devices: 1, webhooks: ["Indy"], webhookProblems: ["Driver: url must be https"]))
    }

    func testAnOlderRelayWithoutHealthStillCountsAsReachable() async throws {
        let relay = ScriptedRelay([.json(404, #"{"error":"not found"}"#)])
        let health = try await client(relay).health(of: endpoint)
        XCTAssertEqual(health, RelayHealth(ok: true, apns: nil, devices: nil, webhooks: [], webhookProblems: []))
    }

    func testHealthWithAWrongTokenFails() async {
        let relay = ScriptedRelay([.json(401, "{}")])
        do {
            _ = try await client(relay).health(of: endpoint)
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? RelayError, .unauthorized)
        }
    }
}

final class RelayEndpointTests: XCTestCase {

    func testAnEmptyAddressIsNotTheOwnersRelayOnStoreBuilds() {
        // CI / standard builds leave defaultAddress empty so empty input cannot hit the
        // owner's Worker (legal C15). Owner builds still resolve blank → ownerAddress.
        if BuildFlavor.current == .owner {
            let endpoint = RelayEndpoint(address: "  ", token: " secret \n")
            XCTAssertEqual(endpoint?.base.absoluteString, RelayEndpoint.ownerAddress)
            XCTAssertEqual(endpoint?.token, "secret")
        } else {
            XCTAssertNil(RelayEndpoint(address: "  ", token: " secret \n"))
            XCTAssertTrue(RelayEndpoint.defaultAddress.isEmpty)
        }
    }

    func testTheOwnersRelayAddressIsExplicit() throws {
        let endpoint = try XCTUnwrap(RelayEndpoint(address: RelayEndpoint.ownerAddress, token: "secret"))
        XCTAssertEqual(endpoint.base.absoluteString, "https://phoenix-fox-relay.cinderandcrown.workers.dev")
    }

    func testNoTokenMeansNotConfigured() {
        XCTAssertNil(RelayEndpoint(address: "", token: ""))
        XCTAssertNil(RelayEndpoint(address: "https://relay.test", token: "   "))
    }

    func testTrailingSlashesAreDropped() throws {
        XCTAssertEqual(RelayEndpoint(address: "https://relay.test//", token: "t")?.base.absoluteString, "https://relay.test")
        XCTAssertEqual(RelayEndpoint(address: "https://relay.test/base/", token: "t")?.base.absoluteString, "https://relay.test/base")
    }

    func testTheTokenIsNeverSentOverPlainHTTPToTheInternet() {
        XCTAssertNil(RelayEndpoint(address: "http://relay.example.com", token: "t"))
        XCTAssertNil(RelayEndpoint(address: "http://8.8.8.8", token: "t"))
        XCTAssertNil(RelayEndpoint(address: "http://172.32.0.1", token: "t"))
        XCTAssertNil(RelayEndpoint(address: "http://localhost.example.com", token: "t"))
    }

    func testPlainHTTPIsAllowedOnTheLocalNetwork() {
        for address in ["http://localhost:8787", "http://127.0.0.1:8787", "http://192.168.1.20:8787", "http://10.0.0.5", "http://172.16.4.1", "http://relay.local"] {
            XCTAssertNotNil(RelayEndpoint(address: address, token: "t"), address)
        }
    }

    func testAddressesThatAreNotARelayAreRejected() {
        for address in ["relay.test", "ftp://relay.test", "https://", "https://user:pass@relay.test", "https://relay.test?x=1", "https://relay.test#frag", "not a url"] {
            XCTAssertNil(RelayEndpoint(address: address, token: "t"), address)
        }
    }
}

final class PushEnvironmentTests: XCTestCase {

    private func profile(_ environment: String?) -> Data {
        let entry = environment.map { "<key>aps-environment</key>\n\t\t<string>\($0)</string>" } ?? ""
        let plist = "<plist><dict><key>Entitlements</key><dict>\(entry)<key>application-identifier</key><string>X.com.example</string></dict></dict></plist>"
        // A real profile wraps the property list in signed binary data.
        return Data([0x30, 0x82, 0xFF, 0x00]) + Data(plist.utf8) + Data([0x00, 0xA0, 0xFE])
    }

    func testABuildWithoutAProfileUsesProduction() {
        XCTAssertEqual(PushEnvironment.detect(provisioningProfile: nil), .production)
    }

    func testADevelopmentProfileUsesSandbox() {
        XCTAssertEqual(PushEnvironment.detect(provisioningProfile: profile("development")), .sandbox)
    }

    func testAProductionProfileUsesProduction() {
        XCTAssertEqual(PushEnvironment.detect(provisioningProfile: profile("production")), .production)
    }

    func testAProfileWithoutPushUsesProduction() {
        XCTAssertEqual(PushEnvironment.detect(provisioningProfile: profile(nil)), .production)
    }
}

final class RelayCheckTests: XCTestCase {

    func testAHealthyRelayIsDescribedInFull() {
        let health = RelayHealth(ok: true, apns: true, devices: 1, webhooks: ["Indy", "Driver"], webhookProblems: ["Rally: url must be https"])
        let outcome = RelayCheck.describe(.success(health), address: "")
        XCTAssertTrue(outcome.isGood)
        XCTAssertEqual(outcome.line, "Connected. Push alerts are set up. Webhooks: Indy, Driver. Webhook problems: Rally: url must be https.")
    }

    func testAnOlderRelayIsJustConnected() {
        let health = RelayHealth(ok: true, apns: nil, devices: nil, webhooks: [], webhookProblems: [])
        XCTAssertEqual(RelayCheck.describe(.success(health), address: "").line, "Connected.")
    }

    func testMissingPushIsSaid() {
        let health = RelayHealth(ok: true, apns: false, devices: 0, webhooks: [], webhookProblems: [])
        XCTAssertEqual(RelayCheck.describe(.success(health), address: "").line, "Connected. Push alerts are not set up on the relay.")
    }

    func testFailuresSayWhatToDo() {
        XCTAssertEqual(RelayCheck.describe(.failure(.unauthorized), address: "").line, "The relay did not accept the token. Check it in Settings.")
        XCTAssertEqual(RelayCheck.describe(.failure(.notConfigured), address: "").line, "Enter the relay token first.")
        XCTAssertEqual(RelayCheck.describe(.failure(.notConfigured), address: "http://example.com").line, "That address can't be used. It must start with https.")
        XCTAssertFalse(RelayCheck.describe(.failure(.offline), address: "").isGood)
    }
}

#if canImport(UserNotifications)
final class PushAlertsTests: XCTestCase {

    func testEverySystemAnswerMapsToARow() {
        XCTAssertEqual(PushAlerts.Status(.notDetermined), .notAsked)
        XCTAssertEqual(PushAlerts.Status(.authorized), .on)
        XCTAssertEqual(PushAlerts.Status(.provisional), .on)
        XCTAssertEqual(PushAlerts.Status(.ephemeral), .on)
        XCTAssertEqual(PushAlerts.Status(.denied), .off)
    }

    func testEachRowSaysWhetherAlertsAreOn() {
        XCTAssertEqual(PushAlerts.Status.on.line, "On.")
        XCTAssertTrue(PushAlerts.Status.notAsked.line.hasPrefix("Off."))
        XCTAssertTrue(PushAlerts.Status.off.line.contains("iOS Settings"))
    }
}
#endif
