// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The HTTP client for the Phoenix Fox relay. The contract is in `docs/RELAY_API.md`.
///
/// The client holds no state and touches nothing but its transport, so it can be used
/// from any task, and four bots can be asked at once.
struct RelayClient: Sendable {
    var transport: any RelayTransport = URLSessionRelayTransport()
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    var now: @Sendable () -> Date = { Date() }

    /// How long one ask may take, from sending it to hearing the reply.
    static let replyDeadline: TimeInterval = 90
    /// The relay holds a reply poll open for at most this many seconds.
    static let replyWait = 20
    static let inboxWait = 25
    /// The relay refuses a body over 1.2 MB. This leaves room for the text around the images.
    static let imageBudget = 780_000

    // MARK: Ask

    /// Sends an ask and waits for the reply.
    ///
    /// The ask carries its own id, so sending it again after a dropped connection cannot
    /// create a second one. Once the relay has the ask, a failed poll is retried until the
    /// deadline, because the bot may already be working on it.
    func ask(_ ask: RelayAsk, to endpoint: RelayEndpoint) async throws -> [RelayReply] {
        // Fail fast when a real /health says no bot can answer — a 90s poll with nobody
        // listening feels like a hang. Legacy relays without /health (or a 404) still proceed.
        if let health = try? await knownHealth(of: endpoint) {
            let wanted = ask.targetBot.trimmingCharacters(in: .whitespacesAndNewlines)
            if health.webhooks.isEmpty {
                throw RelayError.noBotConnected(wanted: wanted.isEmpty ? nil : wanted)
            }
            if !wanted.isEmpty {
                let names = health.webhooks.map { $0.lowercased() }
                if !names.contains(wanted.lowercased()) {
                    throw RelayError.noBotConnected(wanted: wanted)
                }
            }
        }

        let deadline = now().addingTimeInterval(Self.replyDeadline)
        let body = try JSONEncoder().encode(ask)

        var attempt = 0
        while true {
            attempt += 1
            do {
                _ = try await send(endpoint, "POST", "/ask", body: body, timeout: 30)
                break
            } catch let error as RelayError where error.isTemporary && attempt < 3 {
                try await sleep(.seconds(attempt))
            }
        }

        let path = "/reply/\(ask.id)?wait=\(Self.replyWait)"
        while now() < deadline {
            let asked = now()
            do {
                let data = try await send(endpoint, "GET", path, timeout: TimeInterval(Self.replyWait + 10))
                let answer = try decode(ReplyBody.self, from: data)
                if answer.status == "ready" { return answer.spokenReplies }
            } catch let error as RelayError where error.isTemporary {
                try await sleep(.seconds(1))
                continue
            }
            // The relay normally holds the poll open. If something answered "pending" at
            // once, wait before asking again instead of spinning.
            if now().timeIntervalSince(asked) < 1 { try await sleep(.seconds(1)) }
        }
        throw RelayError.noReply
    }

    // MARK: Inbox

    /// Waits up to 25 seconds for pushed messages. The relay removes what it returns.
    func inbox(from endpoint: RelayEndpoint) async throws -> [RelayPush] {
        let data = try await send(endpoint, "GET", "/inbox?wait=\(Self.inboxWait)", timeout: TimeInterval(Self.inboxWait + 15))
        return try decode(InboxBody.self, from: data).messages.filter { !$0.text.isEmpty }
    }

    // MARK: Device

    /// Registers this phone's push token, and which of Apple's push services it belongs to.
    func registerDevice(token: String, environment: PushEnvironment, with endpoint: RelayEndpoint) async throws {
        let body = try JSONEncoder().encode(DeviceBody(token: token, platform: "ios", environment: environment.rawValue))
        _ = try await send(endpoint, "POST", "/device", body: body, timeout: 20)
    }

    // MARK: Health

    /// Checks that the relay is reachable and accepts the token.
    /// A relay from before `/health` existed answers 404 once the token has passed, which is success too.
    func health(of endpoint: RelayEndpoint) async throws -> RelayHealth {
        do {
            return try await knownHealth(of: endpoint)
        } catch RelayError.server(status: 404) {
            return RelayHealth(ok: true, apns: nil, devices: nil, webhooks: [], webhookProblems: [])
        }
    }

    /// `/health` when the route exists. Throws on 404 so callers that need webhook presence
    /// do not treat a legacy empty stub as "no bots connected".
    func knownHealth(of endpoint: RelayEndpoint) async throws -> RelayHealth {
        let data = try await send(endpoint, "GET", "/health", timeout: 15)
        return try decode(RelayHealth.self, from: data)
    }

    // MARK: Plumbing

    private func send(
        _ endpoint: RelayEndpoint,
        _ method: String,
        _ path: String,
        body: Data? = nil,
        timeout: TimeInterval
    ) async throws -> Data {
        guard let url = URL(string: endpoint.base.absoluteString + path) else { throw RelayError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let result: (data: Data, response: URLResponse)
        do {
            result = try await transport.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw RelayError(error)
        }
        try Task.checkCancellation()
        guard let http = result.response as? HTTPURLResponse else { throw RelayError.malformed }
        if (200...299).contains(http.statusCode) { return result.data }
        throw RelayError(status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
    }

    private func decode<Body: Decodable>(_ type: Body.Type, from data: Data) throws -> Body {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw RelayError.malformed
        }
    }

    /// Sent on every request. Cloudflare turns away clients that send no recognisable agent.
    static let userAgent: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        return "PhoenixFox/\(version) (build \(build); iOS \(system.majorVersion).\(system.minorVersion))"
    }()
}

// MARK: - Transport

/// The one thing the client needs from the network, so tests can stand in for the relay.
protocol RelayTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionRelayTransport: RelayTransport {
    /// No cookies, no cache, no credential store: every request carries only the bearer.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await Self.session.data(for: request)
    }
}

// MARK: - Endpoint

/// Where the relay is and the token that opens it.
struct RelayEndpoint: Sendable, Equatable {
    /// The owner's relay. Used when Settings holds no other address.
    static let defaultAddress = "https://phoenix-fox-relay.cinderandcrown.workers.dev"

    let base: URL
    let token: String

    /// Fails when there is no token or the address cannot be used.
    /// The token is a password, so the address must be https. Plain http is accepted only
    /// for a relay on this phone's own network, where a developer may be running one.
    init?(address: String, token: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = Self.defaultAddress }
        while text.hasSuffix("/") { text.removeLast() }
        guard !token.isEmpty,
              let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              scheme == "https" || (scheme == "http" && Self.isLocal(host)),
              let base = components.url
        else { return nil }
        self.base = base
        self.token = token
    }

    /// Whether a host is on this device or its local network.
    static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4, host.split(separator: ".").count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}

// MARK: - Messages

/// What the phone sends to a bot.
struct RelayAsk: Encodable, Sendable, Equatable {
    struct Turn: Encodable, Sendable, Equatable {
        var role: String
        var text: String
    }

    var id: String = UUID().uuidString
    /// The request with the wake word and filler removed.
    var text: String
    /// What was heard, word for word.
    var transcript: String
    var timestamp: String = ISO8601DateFormatter().string(from: Date())
    var intent: String
    var targetBot: String
    var context: [Turn] = []
    var replyTo: String?
    /// JPEG data. The first travels as `image`, the rest as `images`.
    var images: [Data] = []

    private enum CodingKeys: String, CodingKey {
        case id, text, transcript, timestamp, intent, context, image, images
        case targetBot = "target_bot"
        case replyTo = "reply_to"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(intent, forKey: .intent)
        try container.encode(targetBot, forKey: .targetBot)
        try container.encode(context, forKey: .context)
        try container.encodeIfPresent(replyTo, forKey: .replyTo)
        if let first = images.first {
            try container.encode(first.base64EncodedString(), forKey: .image)
        }
        if images.count > 1 {
            try container.encode(images.dropFirst().map { $0.base64EncodedString() }, forKey: .images)
        }
    }
}

struct RelayReply: Equatable, Sendable {
    var text: String
    var fromBot: String
}

/// A message a bot pushed to the phone.
struct RelayPush: Decodable, Equatable, Sendable {
    var id: String
    var text: String
    var fromBot: String
    var priority: Priority

    enum Priority: String, Sendable {
        case urgent, normal, low
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, priority
        case fromBot = "from_bot"
    }

    init(id: String, text: String, fromBot: String, priority: Priority) {
        self.id = id
        self.text = text
        self.fromBot = fromBot
        self.priority = priority
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        fromBot = try container.decodeIfPresent(String.self, forKey: .fromBot) ?? ""
        let raw = try container.decodeIfPresent(String.self, forKey: .priority) ?? ""
        priority = Priority(rawValue: raw) ?? .normal
    }
}

/// What `GET /health` reports. Fields are nil when the relay is too old to report them.
struct RelayHealth: Decodable, Equatable, Sendable {
    var ok: Bool
    var apns: Bool?
    var devices: Int?
    var webhooks: [String]
    var webhookProblems: [String]

    private enum CodingKeys: String, CodingKey {
        case ok, apns, devices, webhooks
        case webhookProblems = "webhook_problems"
    }

    init(ok: Bool, apns: Bool?, devices: Int?, webhooks: [String], webhookProblems: [String]) {
        self.ok = ok
        self.apns = apns
        self.devices = devices
        self.webhooks = webhooks
        self.webhookProblems = webhookProblems
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        apns = try container.decodeIfPresent(Bool.self, forKey: .apns)
        devices = try container.decodeIfPresent(Int.self, forKey: .devices)
        webhooks = try container.decodeIfPresent([String].self, forKey: .webhooks) ?? []
        webhookProblems = try container.decodeIfPresent([String].self, forKey: .webhookProblems) ?? []
    }
}

/// Which of Apple's two push services a device token belongs to.
enum PushEnvironment: String, Sendable {
    case production, sandbox

    /// The service this build's push token belongs to.
    static let current: PushEnvironment = {
        #if targetEnvironment(simulator)
        return .sandbox
        #else
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
        return detect(provisioningProfile: profile)
        #endif
    }()

    /// A build from TestFlight or the App Store carries no provisioning profile and uses
    /// production. A build installed from Xcode carries one that names its push service.
    static func detect(provisioningProfile: Data?) -> PushEnvironment {
        guard let provisioningProfile else { return .production }
        // The profile is a signed container around a property list in plain text.
        let text = String(decoding: provisioningProfile, as: UTF8.self)
        guard let key = text.range(of: "<key>aps-environment</key>"),
              let open = text.range(of: "<string>", range: key.upperBound..<text.endIndex),
              let close = text.range(of: "</string>", range: open.upperBound..<text.endIndex)
        else { return .production }
        return text[open.upperBound..<close.lowerBound] == "development" ? .sandbox : .production
    }
}

private struct ReplyBody: Decodable {
    struct Part: Decodable {
        var text: String?
        var fromBot: String?

        private enum CodingKeys: String, CodingKey {
            case text
            case fromBot = "from_bot"
        }
    }

    var status: String?
    var text: String?
    var fromBot: String?
    var replies: [Part]?

    private enum CodingKeys: String, CodingKey {
        case status, text, replies
        case fromBot = "from_bot"
    }

    /// One entry per bot that said something. Falls back to the joined text of an older relay.
    var spokenReplies: [RelayReply] {
        let parts = (replies ?? []).compactMap { part -> RelayReply? in
            guard let text = part.text, !text.isEmpty else { return nil }
            return RelayReply(text: text, fromBot: part.fromBot ?? "")
        }
        if !parts.isEmpty { return parts }
        guard let text, !text.isEmpty else { return [] }
        return [RelayReply(text: text, fromBot: fromBot ?? "")]
    }
}

private struct InboxBody: Decodable {
    var messages: [RelayPush]

    private enum CodingKeys: String, CodingKey {
        case messages
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decodeIfPresent([RelayPush].self, forKey: .messages) ?? []
    }
}

private struct DeviceBody: Encodable {
    var token: String
    var platform: String
    var environment: String
}

// MARK: - Errors

/// Why a relay call failed. Each description is a sentence that can be spoken to the wearer.
enum RelayError: Error, Equatable, LocalizedError {
    /// No usable address or no token.
    case notConfigured
    /// The relay refused the token.
    case unauthorized
    /// The network in front of the relay refused the request.
    case blocked
    case rateLimited(retryAfter: TimeInterval)
    case tooLarge
    case server(status: Int)
    /// The phone has no connection, or the relay could not be reached.
    case offline
    /// The relay took the ask, and no bot answered in time.
    case noReply
    /// Health shows no bot webhook (or the named bot is missing), so a long poll would hang.
    case noBotConnected(wanted: String?)
    /// The relay answered with something this app does not understand.
    case malformed

    init(status: Int, retryAfter: String?) {
        switch status {
        case 401: self = .unauthorized
        case 403: self = .blocked
        case 413: self = .tooLarge
        case 429: self = .rateLimited(retryAfter: retryAfter.flatMap(TimeInterval.init) ?? 60)
        default: self = .server(status: status)
        }
    }

    init(_ error: URLError) {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .timedOut, .dataNotAllowed, .internationalRoamingOff, .secureConnectionFailed:
            self = .offline
        default:
            self = .server(status: 0)
        }
    }

    /// Whether trying again soon could succeed.
    var isTemporary: Bool {
        switch self {
        case .offline: return true
        case .server(let status): return status == 0 || status >= 500 || status == 408
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add the relay token in Settings."
        case .unauthorized: return "The relay did not accept the token. Check it in Settings."
        case .blocked: return "The relay's network refused the request."
        case .rateLimited: return "Too many requests. Try again in a minute."
        case .tooLarge: return "That was too large to send."
        case .server(let status): return status == 0 ? "The relay could not be reached." : "The relay returned an error, \(status)."
        case .offline: return "The phone is offline, so I could not reach the relay."
        case .noReply: return "No reply came back in time."
        case .noBotConnected(let wanted):
            if let wanted, !wanted.isEmpty {
                return "\(wanted) is not connected to the relay. Start that bot, then try again."
            }
            return "No bot is connected to the relay. Start Fire Fox, Indy, Driver, or Rally, then try again."
        case .malformed: return "The relay sent something I could not read."
        }
    }
}
