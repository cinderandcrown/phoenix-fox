// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Smart Capture. The glasses stream stays on, so the hardware light stays on.
// On-device scoring picks the frames worth a check. Each check goes only to the owner's own
// Phoenix rig, over the owner's private network. The rig keeps or skips. A kept frame is
// sealed into an outbox on this phone and handed to the rig's moments archive, and the
// outbox copy is deleted once the rig says it has it. Nothing goes to Grok, any other cloud
// service or the Photos library. With no rig set up, Smart Capture doesn't start.

import Contacts
import CryptoKit
import Foundation
import SwiftUI
import UIKit

@MainActor
final class SmartCapture: ObservableObject {
    static let shared = SmartCapture()

    @Published private(set) var isRunning = false
    private var task: Task<Void, Never>?
    private var startedAt = Date()
    private var rigChecks = 0
    private var kept = 0
    private var announcedCap = false
    private var announcedOffline = false

    private init() {}

    func command(_ text: String) async -> String? {
        let lower = text.lowercased()
        if lower.contains("smart capture") && (lower.contains("off") || lower.contains("stop")) {
            return await stop()
        }
        if lower.contains("smart capture") && (lower.contains("on") || lower.contains("start")) {
            return await start()
        }
        let looking = lower.contains("show me") || lower.contains("what did you capture") || lower.contains("what did smart capture")
        let topic = lower.contains("receipt") || lower.contains("whiteboard") || lower.contains("business card")
            || lower.contains("highlight") || lower.contains("capture")
        if looking && topic {
            let spoken = SmartCaptureIndex.speak(matching: text)
            CompanionRuntime.shared.caption = spoken
            return spoken
        }
        return nil
    }

    func start() async -> String {
        if isRunning {
            return "Smart capture is already on. The glasses light is on."
        }
        guard SettingsManager.shared.settings.isPhoenixRigConfigured else {
            return "Smart capture needs your Phoenix rig set up in Settings. I didn't turn the camera on."
        }
        guard GlassesManager.shared.isRegistered else {
            return "Connect the glasses first. Smart capture uses their camera, and the light stays on."
        }
        isRunning = true
        startedAt = Date()
        rigChecks = 0
        kept = 0
        announcedCap = false
        announcedOffline = false
        let minutes = max(SettingsManager.shared.settings.smartCaptureMinutes, 1)
        CompanionRuntime.shared.showCamera(on: true, line: "Smart capture on. The glasses light is on.")
        NotificationCenter.default.post(name: .phoenixKeepListening, object: nil)
        task = Task { await self.loop() }
        Task { await MomentOutbox.flush(settings: SettingsManager.shared.settings) }
        return "Smart capture is on. The glasses light stays on. I'll stop after \(minutes) minutes, or when you say smart capture off."
    }

    func stop() async -> String {
        let was = isRunning
        isRunning = false
        task?.cancel()
        task = nil
        let watching = CompanionRuntime.shared.isWatching
        await releaseCamera()
        if !was { return "Smart capture is already off." }
        if watching { return "Smart capture is off. The glasses light stays on because you are still watching." }
        return "Smart capture is off. The camera is off."
    }

    private func loop() async {
        await GlassesManager.shared.startStreaming(for: .smartCapture)
        guard isRunning else { return }
        guard GlassesManager.shared.isStreaming else {
            await finish("I couldn't start the glasses camera, so smart capture is off.")
            return
        }
        var lastThumb: [UInt8] = []
        var lastSent = Date.distantPast
        while !Task.isCancelled && isRunning {
            let settings = SettingsManager.shared.settings
            if Date().timeIntervalSince(startedAt) >= Double(max(settings.smartCaptureMinutes, 1)) * 60 {
                await finish("Smart capture time is up. The camera is off.")
                return
            }
            if kept >= max(settings.smartCaptureMax, 1) {
                await finish("That's the capture limit. Smart capture is off. The camera is off.")
                return
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard isRunning, let image = GlassesManager.shared.lastFrame, let thumb = Thumbnail.bytes(image) else { continue }
            let previous = lastThumb
            lastThumb = thumb
            guard CaptureScore.candidate(previous: previous, next: thumb, sensitivity: settings.smartCaptureSensitivity) else { continue }
            guard Date().timeIntervalSince(lastSent) > 5 else { continue }
            if rigChecks >= max(settings.smartCaptureCostCap, 1) {
                if !announcedCap {
                    announcedCap = true
                    TTSService.shared.speakAmbient("That's the check limit for this session. I won't send more frames to the rig. The light stays on until you stop it or the timer ends.")
                }
                continue
            }
            lastSent = Date()
            rigChecks += 1
            guard let jpeg = ImageBudget.jpeg(image.jpegData(compressionQuality: 0.55)) else { continue }
            await judge(jpeg, at: Date(), settings: settings)
        }
    }

    private func judge(_ jpeg: Data, at capturedAt: Date, settings: AppSettings) async {
        let categories = enabledCategories(settings)
        guard !categories.isEmpty else { return }
        let system = PhoenixRig.judgeSystemPrompt(categories: categories)
        guard let raw = await PhoenixRig.judge(jpeg: jpeg, system: system, settings: settings) else {
            if !announcedOffline {
                announcedOffline = true
                TTSService.shared.speakAmbient("I can't reach your Phoenix rig, so I'm not keeping anything right now. Nothing goes anywhere else.")
            }
            return
        }
        announcedOffline = false
        guard let verdict = CaptureVerdict.parse(raw),
              verdict.keep,
              enabled(verdict.action, settings: settings) else { return }
        let caption = verdict.caption.isEmpty ? "Kept a \(verdict.action)." : verdict.caption
        let moment = PhoenixRig.Moment(
            jpeg: jpeg, capturedAt: capturedAt, timeZone: TimeZone.current.identifier,
            caption: caption, tags: verdict.tags, action: verdict.action
        )
        guard MomentOutbox.add(moment) else {
            TTSService.shared.speakAmbient("I wanted to keep that frame, but I couldn't seal it on this phone, so I let it go.")
            return
        }
        SmartCaptureIndex.remember(CaptureItem(
            caption: caption,
            tags: verdict.tags,
            action: verdict.action,
            at: capturedAt,
            highlight: verdict.action == "highlight"
        ))
        kept += 1
        CompanionRuntime.shared.caption = caption
        var spoken = caption
        if settings.smartCaptureAutoRoute {
            let next = route(verdict)
            if !next.isEmpty { spoken += " " + next }
        }
        TTSService.shared.speakAmbient(spoken)
        Task { await MomentOutbox.flush(settings: settings) }
    }

    private func route(_ verdict: CaptureVerdict) -> String {
        switch verdict.action {
        case "receipt":
            return "Kept on your rig with the receipts."
        case "card":
            let name = verdict.contact?.name ?? ""
            let phone = verdict.contact?.phone ?? ""
            let email = verdict.contact?.email ?? ""
            guard !name.isEmpty else { return "I kept the card, but there wasn't a name to save." }
            Task { _ = await ContactCard.save(name: name, phone: phone, email: email) }
            return "Saving \(name) to Contacts."
        case "whiteboard":
            SecureNotes.remember(verdict.caption)
            return "Saved the note on this phone."
        case "highlight":
            return "Marked as a highlight for the morning brief."
        default:
            return ""
        }
    }

    private func finish(_ line: String) async {
        isRunning = false
        task = nil
        await releaseCamera()
        TTSService.shared.speak(line)
    }

    private func releaseCamera() async {
        if CompanionRuntime.shared.isWatching { return }
        if GlassesManager.shared.isStreaming, !GuideMode.shared.isOn {
            await GlassesManager.shared.stopStreaming()
        }
        CompanionRuntime.shared.showCamera(on: false, line: "Listening for Hey Phoenix. The mic indicator stays visible.")
    }

    private func enabledCategories(_ settings: AppSettings) -> [String] {
        var names: [String] = []
        if settings.smartCaptureReceipts { names.append("receipt") }
        if settings.smartCaptureCards { names.append("business card") }
        if settings.smartCaptureBoards { names.append("whiteboard") }
        if settings.smartCaptureHighlights { names.append("scenic or people moment") }
        return names
    }

    private func enabled(_ action: String, settings: AppSettings) -> Bool {
        switch action {
        case "receipt": return settings.smartCaptureReceipts
        case "card": return settings.smartCaptureCards
        case "whiteboard": return settings.smartCaptureBoards
        case "highlight": return settings.smartCaptureHighlights
        default: return false
        }
    }
}

enum CaptureScore {
    /// A frame is a candidate when the scene changed and the thumbnail has some contrast.
    /// The threshold is the sensitivity setting. Higher means fewer frames.
    static func candidate(previous: [UInt8], next: [UInt8], sensitivity: Double) -> Bool {
        guard !previous.isEmpty, previous.count == next.count else { return false }
        let delta = FrameChange.difference(previous, next)
        guard delta >= sensitivity else { return false }
        let mean = Double(next.reduce(0) { $0 + Int($1) }) / Double(next.count)
        var variance = 0.0
        for pixel in next {
            let distance = Double(pixel) - mean
            variance += distance * distance
        }
        variance /= Double(next.count)
        let contrast = min(variance / 2500, 1)
        return (delta * 0.75 + contrast * 0.25) >= sensitivity
    }
}

struct CaptureVerdict {
    var keep: Bool
    var tags: [String]
    var caption: String
    var action: String
    var contact: Card?

    struct Card {
        var name: String
        var phone: String
        var email: String
    }

    static func parse(_ raw: String) -> CaptureVerdict? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") else { return nil }
        let slice = String(raw[start...end])
        guard let data = slice.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let contactJSON = json["contact"] as? [String: Any]
        let contact = Card(
            name: contactJSON?["name"] as? String ?? "",
            phone: contactJSON?["phone"] as? String ?? "",
            email: contactJSON?["email"] as? String ?? ""
        )
        let tags = (json["tags"] as? [String]) ?? []
        return CaptureVerdict(
            keep: json["keep"] as? Bool ?? false,
            tags: tags,
            caption: json["caption"] as? String ?? "",
            action: json["action"] as? String ?? "none",
            contact: contact
        )
    }
}

struct CaptureItem: Codable {
    var caption: String
    var tags: [String]
    var action: String
    var at: Date
    var highlight: Bool
}

enum SmartCaptureIndex {
    static func remember(_ item: CaptureItem) {
        var items = load()
        items.append(item)
        if items.count > 200 { items.removeFirst(items.count - 200) }
        save(items)
    }

    static func speak(matching query: String) -> String {
        let lower = query.lowercased()
        let today = lower.contains("today")
        let matches = load().filter { item in
            if today && !Calendar.current.isDateInToday(item.at) { return false }
            if lower.contains("receipt") { return item.action == "receipt" || item.tags.contains(where: { $0.lowercased() == "receipt" }) }
            if lower.contains("whiteboard") { return item.action == "whiteboard" }
            if lower.contains("card") { return item.action == "card" }
            if lower.contains("highlight") { return item.highlight }
            return true
        }
        guard !matches.isEmpty else { return "I don't have a matching capture." }
        let lines = matches.suffix(5).map(\.caption).joined(separator: " ")
        return "I kept \(matches.count). \(lines)"
    }

    static func reel() -> String {
        let start = Calendar.current.date(byAdding: .hour, value: -36, to: Date()) ?? Date()
        let items = load().filter { $0.highlight && $0.at >= start }
        guard !items.isEmpty else { return "" }
        return "Highlights from smart capture: " + items.suffix(4).map(\.caption).joined(separator: " ")
    }

    private static func key() -> SymmetricKey {
        let account = "phoenix.capture.key"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        let data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
        return SymmetricKey(data: data)
    }

    private static func file() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("phoenix-captures.enc")
    }

    private static func load() -> [CaptureItem] {
        guard let sealed = try? Data(contentsOf: file()),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let clear = try? AES.GCM.open(box, using: key()) else { return [] }
        return (try? JSONDecoder().decode([CaptureItem].self, from: clear)) ?? []
    }

    private static func save(_ items: [CaptureItem]) {
        guard let clear = try? JSONEncoder().encode(items),
              let box = try? AES.GCM.seal(clear, using: key()),
              let combined = box.combined else { return }
        try? combined.write(to: file())
    }
}

/// The owner's own Phoenix rig: the only place Smart Capture frames go.
enum PhoenixRig {
    /// The camera name the rig files Smart Capture moments under.
    static let camera = "Nick's Eye"

    /// A checked rig base URL ending in /v1, or nil. Only https is accepted, because the frames
    /// and the key cross the network. No user info, query or fragment.
    static func baseURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty, let parts = URLComponents(string: text),
              parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        if !text.hasSuffix("/v1") { text += "/v1" }
        return URL(string: text)
    }

    static func judgeSystemPrompt(categories: [String]) -> String {
        """
        You judge one glasses frame for Smart Capture. Reply with JSON only, no markdown:
        {"keep":false,"tags":[],"caption":"","action":"none","contact":{"name":"","phone":"","email":""}}
        keep is true only for a clear \(categories.joined(separator: ", ")).
        action is one of receipt, card, whiteboard, highlight, none.
        caption is one short spoken sentence. contact is filled only for a business card.
        """
    }

    /// The model to name in requests. Empty settings let the rig pick its own vision model.
    static func model(_ configured: String) -> String {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "phoenix" : trimmed
    }

    /// The chat/completions body for one keep-or-skip check.
    static func judgeBody(jpeg: Data, system: String, model: String) -> Data? {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": [
                    ["type": "text", "text": "Judge this frame."],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + jpeg.base64EncodedString()]],
                ]],
            ],
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// The assistant text from an OpenAI-style chat/completions reply.
    static func content(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { return nil }
        if let text = message["content"] as? String { return text }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// One kept frame, as the rig's moments archive receives it. The JPEG is the frame exactly
    /// as judged, never re-encoded, and its SHA-256 lets the rig prove it arrived unchanged.
    struct Moment: Codable, Equatable {
        var id: String = UUID().uuidString
        var jpeg: Data
        var sha256: String
        var capturedAt: Date
        var timeZone: String
        var camera: String
        var caption: String
        var tags: [String]
        var action: String

        init(jpeg: Data, capturedAt: Date, timeZone: String, caption: String, tags: [String], action: String) {
            self.jpeg = jpeg
            self.sha256 = PhoenixRig.sha256Hex(jpeg)
            self.capturedAt = capturedAt
            self.timeZone = timeZone
            self.camera = PhoenixRig.camera
            self.caption = caption
            self.tags = tags
            self.action = action
        }
    }

    /// The POST {rig}/moments body. Field names are the contract the rig's moments route reads.
    static func momentBody(_ moment: Moment) -> Data? {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime]
        stamp.timeZone = TimeZone(identifier: moment.timeZone) ?? .current
        let body: [String: Any] = [
            "id": moment.id,
            "image_jpeg_base64": moment.jpeg.base64EncodedString(),
            "sha256": moment.sha256,
            "captured_at": stamp.string(from: moment.capturedAt),
            "time_zone": moment.timeZone,
            "camera": moment.camera,
            "source": "Phoenix Fox Smart Capture",
            "caption": moment.caption,
            "tags": moment.tags,
            "action": moment.action,
        ]
        return try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// Requests leave no cache or cookies behind on the phone.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    private static func request(_ path: String, body: Data, settings: AppSettings, timeout: TimeInterval) -> URLRequest? {
        guard let base = baseURL(settings.phoenixRigURL), !settings.phoenixRigKey.isEmpty else { return nil }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.phoenixRigKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = timeout
        return request
    }

    /// Asks the rig to keep or skip one frame. Nil when the rig can't be reached or refuses.
    @MainActor
    static func judge(jpeg: Data, system: String, settings: AppSettings) async -> String? {
        guard let body = judgeBody(jpeg: jpeg, system: system, model: model(settings.phoenixRigModel)),
              let request = request("chat/completions", body: body, settings: settings, timeout: 45),
              let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(status) else { return nil }
        return content(from: data)
    }

    /// Hands one moment to the rig. True only when the rig answers with a 2xx.
    @MainActor
    static func upload(_ moment: Moment, settings: AppSettings) async -> Bool {
        guard let body = momentBody(moment),
              let request = request("moments", body: body, settings: settings, timeout: 60),
              let (_, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return false }
        return (200...299).contains(status)
    }
}

/// Kept moments waiting for the rig, sealed with a key that never leaves this phone's Keychain.
/// The folder is left out of device backups. A moment is deleted here only after the rig has it.
@MainActor
enum MomentOutbox {
    private static let account = "phoenix.moments.key"
    private static var flushing = false

    @discardableResult
    static func add(_ moment: PhoenixRig.Moment) -> Bool {
        guard let key = key(), let folder = folder(),
              let clear = try? JSONEncoder().encode(moment),
              let box = try? AES.GCM.seal(clear, using: key),
              let combined = box.combined else { return false }
        let file = folder.appendingPathComponent(moment.id + ".sealed")
        return (try? combined.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }

    static var count: Int {
        guard let folder = folder() else { return 0 }
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".sealed") }.count
    }

    /// Sends what is waiting, oldest first, and stops at the first failure to try again later.
    static func flush(settings: AppSettings) async {
        guard !flushing, settings.isPhoenixRigConfigured, let key = key(), let folder = folder() else { return }
        flushing = true
        defer { flushing = false }
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension == "sealed" }
            .sorted { creation($0) < creation($1) }
        for file in files {
            guard let sealed = try? Data(contentsOf: file),
                  let box = try? AES.GCM.SealedBox(combined: sealed),
                  let clear = try? AES.GCM.open(box, using: key),
                  let moment = try? JSONDecoder().decode(PhoenixRig.Moment.self, from: clear) else { continue }
            guard await PhoenixRig.upload(moment, settings: settings) else { return }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func creation(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    private static func folder() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        var folder = base.appendingPathComponent("PhoenixMoments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
        return folder
    }

    /// Nil when the Keychain refuses: nothing is ever written unsealed as a fallback.
    private static func key() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        let data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return nil }
        return SymmetricKey(data: data)
    }
}

enum ContactCard {
    static func save(name: String, phone: String, email: String) async -> Bool {
        let store = CNContactStore()
        let granted = await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { ok, _ in continuation.resume(returning: ok) }
        }
        guard granted else { return false }
        let contact = CNMutableContact()
        let parts = name.split(separator: " ").map(String.init)
        contact.givenName = parts.first ?? name
        if parts.count > 1 { contact.familyName = parts.dropFirst().joined(separator: " ") }
        if !phone.isEmpty {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))]
        }
        if !email.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)]
        }
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        return (try? store.execute(request)) != nil
    }
}

struct SmartCaptureSettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var capture = SmartCapture.shared

    var body: some View {
        Form {
            Section {
                Toggle("Smart capture", isOn: Binding(
                    get: { capture.isRunning },
                    set: { on in Task { if on { _ = await capture.start() } else { _ = await capture.stop() } } }
                ))
            } footer: {
                Text("The glasses light stays on for the whole session. It stops after the timer, or when you say smart capture off.")
            }
            Section {
                TextField("https://your-rig.example/v1", text: $settings.settings.phoenixRigURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Rig key", text: $settings.settings.phoenixRigKey)
                TextField("Model (optional)", text: $settings.settings.phoenixRigModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Phoenix rig")
            } footer: {
                Text(rigFooter)
            }
            Section("Session") {
                Stepper("Minutes: \(settings.settings.smartCaptureMinutes)", value: $settings.settings.smartCaptureMinutes, in: 5...120, step: 5)
                Stepper("Max captures: \(settings.settings.smartCaptureMax)", value: $settings.settings.smartCaptureMax, in: 1...50)
                Stepper("Rig checks: \(settings.settings.smartCaptureCostCap)", value: $settings.settings.smartCaptureCostCap, in: 1...40)
                Picker("Sensitivity", selection: $settings.settings.smartCaptureSensitivity) {
                    Text("Low").tag(0.20)
                    Text("Medium").tag(0.12)
                    Text("High").tag(0.08)
                }
            }
            Section {
                Toggle("Receipts", isOn: $settings.settings.smartCaptureReceipts)
                Toggle("Business cards", isOn: $settings.settings.smartCaptureCards)
                Toggle("Whiteboards", isOn: $settings.settings.smartCaptureBoards)
                Toggle("Highlights", isOn: $settings.settings.smartCaptureHighlights)
                Toggle("Act on kept items", isOn: $settings.settings.smartCaptureAutoRoute)
            } header: {
                Text("Categories")
            } footer: {
                Text("Every kept item goes to your rig. When this is on, cards are also saved to Contacts and whiteboards to notes on this phone. It stays off until you turn it on.")
            }
        }
        .navigationTitle("Smart Capture")
    }

    private var rigFooter: String {
        if !settings.settings.phoenixRigURL.isEmpty && PhoenixRig.baseURL(settings.settings.phoenixRigURL) == nil {
            return "Use your rig's private https address. Plain http isn't accepted."
        }
        let waiting = MomentOutbox.count
        let base = "Frames go only to your own rig. Nothing goes to Grok, the cloud or Photos. Smart capture won't start until this is set up."
        return waiting > 0 ? base + " \(waiting) kept on this phone, waiting for the rig." : base
    }
}
