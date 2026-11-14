// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Hands-free companion actions that stay on public APIs.
// The glasses capture light is the hardware's. This file never turns it off
// and never starts the camera without a spoken request.

import ActivityKit
import AppIntents
import AVFoundation
import Contacts
import CoreLocation
import CryptoKit
import Foundation
import MapKit
import NaturalLanguage
import SwiftUI
import UIKit
import UserNotifications

enum MessageHandoff {
    /// Opens WhatsApp, Messenger, Mail, or Messages with the dictated text filled in.
    /// The wearer still taps send. Nothing is sent silently.
    @MainActor
    static func send(_ utterance: String) async -> String {
        let lower = utterance.lowercased()
        let body = dictatedBody(from: utterance)
        let person = recipientName(in: utterance)
        let phone = await phone(for: person)
        let email = await emailAddress(for: person)
        let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if lower.contains("whatsapp") {
            let urlString = phone.map { "https://wa.me/\($0)?text=\(encoded)" } ?? "https://wa.me/?text=\(encoded)"
            if let url = URL(string: urlString) { await UIApplication.shared.open(url) }
            return "Opened WhatsApp with your words filled in. You still tap send."
        }
        if lower.contains("messenger") {
            if let url = URL(string: "fb-messenger://share?link=\(encoded)") {
                await UIApplication.shared.open(url)
            }
            return "Opened Messenger. You still tap send. A glasses video call is not available."
        }
        if lower.contains("email") || lower.contains("e-mail") {
            let to = email ?? ""
            if let url = URL(string: "mailto:\(to)?body=\(encoded)") { await UIApplication.shared.open(url) }
            return email == nil ? "Opened Mail with the note. Add an address if none was on the contact." : "Opened Mail to \(email!)."
        }
        if let phone, let url = URL(string: "sms:\(phone)&body=\(encoded)") {
            await UIApplication.shared.open(url)
            return "Opened Messages to \(phone). You still tap send."
        }
        await presentShare(body)
        return "Opened the share sheet with your words. Pick WhatsApp, Messages, or Mail on the phone."
    }

    private static func dictatedBody(from utterance: String) -> String {
        let markers = ["saying ", "that ", "to say ", ": "]
        let lower = utterance.lowercased()
        for marker in markers {
            if let range = lower.range(of: marker) {
                return String(utterance[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return utterance
    }

    private static func recipientName(in utterance: String) -> String {
        let lower = utterance.lowercased()
        for prefix in ["to ", "message ", "text ", "email "] {
            if let range = lower.range(of: prefix) {
                var rest = String(utterance[range.upperBound...])
                for stop in [" saying ", " that ", " on whatsapp", " on messenger", " via ", " to say "] {
                    if let cut = rest.lowercased().range(of: stop) {
                        rest = String(rest[..<cut.lowerBound])
                        break
                    }
                }
                return rest.split(separator: " ").prefix(2).joined(separator: " ")
            }
        }
        return ""
    }

    @MainActor
    private static func phone(for name: String) async -> String? {
        guard name.count > 1 else { return nil }
        let digits = name.filter(\.isNumber)
        if digits.count >= 7 { return digits }
        return await contact(name, key: CNContactPhoneNumbersKey) { $0.phoneNumbers.first?.value.stringValue }
    }

    @MainActor
    private static func emailAddress(for name: String) async -> String? {
        await contact(name, key: CNContactEmailAddressesKey) { $0.emailAddresses.first?.value as String? }
    }

    @MainActor
    private static func contact(_ name: String, key: String, pick: (CNContact) -> String?) async -> String? {
        let store = CNContactStore()
        let granted = await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { ok, _ in continuation.resume(returning: ok) }
        }
        guard granted else { return nil }
        let found = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: [key as CNKeyDescriptor])) ?? []
        return found.first.flatMap(pick)?.filter { $0.isNumber || $0 == "+" || $0 == "@" || $0.isLetter || $0 == "." }
    }

    @MainActor
    private static func presentShare(_ text: String) async {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        root.present(controller, animated: true)
    }
}

@MainActor
final class CompanionRuntime: ObservableObject {
    static let shared = CompanionRuntime()

    @Published var cameraOn = false
    @Published var statusLine = "Listening for Jarvis. The mic indicator stays visible."
    @Published var caption = ""

    /// True while watch-this or translation should keep the conversation open.
    var holdsConversation: Bool { cameraOn || translating }
    var isWatching: Bool { watchTask != nil }

    func showCamera(on: Bool, line: String) {
        cameraOn = on
        statusLine = line
        refreshIsland()
    }

    private var watchTask: Task<Void, Never>?
    private var islandUpdate: Task<Void, Never>?
    private var lastThumb: [UInt8] = []
    private var watchSends = 0
    private var translating = false
    private var translationTarget = "English"

    private init() {}

    /// Returns a spoken line when this command is handled here.
    func consume(_ text: String, snapshot: () async -> Data?) async -> String? {
        let lower = text.lowercased()
        if let capture = await SmartCapture.shared.command(text) {
            return capture
        }
        if lower.hasPrefix("reply ") || lower.hasPrefix("answer that ") {
            let body = lower.hasPrefix("reply ") ? String(text.dropFirst(6)) : String(text.dropFirst(12))
            return await replyToInbox(body)
        }
        if lower.contains("take over") || lower.hasPrefix("grok, take over") || lower.hasPrefix("grok take over") {
            return await takeOver(text)
        }
        if lower.contains("watch this") || lower.contains("start watching") {
            startWatch()
            return "Watching. The glasses camera light is on. I only send a frame when the scene changes. Say stop watching."
        }
        if lower.contains("stop watching") {
            let capture = SmartCapture.shared.isRunning
            stopWatch()
            return capture
                ? "Stopped watching. Smart capture is still on, so the glasses light stays on."
                : "Stopped watching. The camera is off."
        }
        if lower.contains("record a clip") || lower.contains("start recording")
            || lower.contains("take a video") || lower.contains("record a video") || lower.contains("start a video") {
            NotificationCenter.default.post(name: .phoenixRecord, object: nil)
            cameraOn = true
            statusLine = "Recording. The glasses camera light is on."
            return "Recording the preview. The glasses light stays on. This is not Meta's 3K camera file. Say stop recording."
        }
        if lower.contains("stop recording") {
            NotificationCenter.default.post(name: .phoenixStopRecord, object: nil)
            cameraOn = false
            statusLine = "Listening for Jarvis. The mic dot stays visible."
            return "Stopped. The clip saves to Photos if the recorder finished."
        }
        if lower.contains("translate to ") || lower.contains("start translating")
            || lower.contains("live translation") || lower.contains("translate this conversation") {
            if let range = lower.range(of: "translate to ") {
                let word = String(text[range.upperBound...]).split(separator: " ").first.map(String.init) ?? "English"
                translationTarget = word
            } else {
                translationTarget = "English"
            }
            translating = true
            NotificationCenter.default.post(name: .phoenixKeepListening, object: nil)
            TranscriptLog.append("Translation on: \(text)")
            caption = "Translating into \(translationTarget). Captions stay on the phone."
            return "I'll translate the next things you say into \(translationTarget) and show the words on the phone. These glasses have no lens captions. Say stop translating."
        }
        if lower.contains("stop translating") {
            translating = false
            caption = ""
            return "Translation off. Say meeting notes if you want a summary."
        }
        if translating {
            let line = await translate(text)
            TranscriptLog.append(line)
            return line
        }
        if lower.contains("summarize the meeting") || lower.contains("meeting notes") {
            return await summarizeMeeting()
        }
        if lower.contains("morning brief") || lower.contains("brief me") {
            return await morningBrief(force: true)
        }
        if lower.contains("when i arrive") || lower.contains("when i get to") {
            return await PlaceReminders.shared.arm(text)
        }
        if lower.contains("task history") || lower.contains("what did they do") {
            let lines = TaskLog.lines()
            return lines.isEmpty ? "No take-over tasks yet." : lines.suffix(4).joined(separator: " ")
        }
        return nil
    }

    func noteListening() {
        if !cameraOn {
            statusLine = "Listening for Jarvis. The mic indicator stays visible."
        }
        refreshIsland()
    }

    func maybeMorningBrief() async {
        let hour = Calendar.current.component(.hour, from: Date())
        guard (5..<11).contains(hour) else { return }
        let key = "phoenix.morning.\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let reel = SmartCaptureIndex.reel()
        guard SettingsManager.shared.settings.isOwnAssistantConfigured || !reel.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: key)
        if SettingsManager.shared.settings.isOwnAssistantConfigured {
            let line = await morningBrief(force: true)
            TTSService.shared.speak(line)
        } else {
            TTSService.shared.speak(reel)
        }
        statusLine = "Morning brief."
    }

    private func replyToInbox(_ text: String) async -> String {
        guard let id = InboxThread.lastId else {
            return "Nothing is waiting in the inbox."
        }
        guard SettingsManager.shared.settings.isOwnAssistantConfigured else {
            return "The relay is not configured, so I can't send that reply."
        }
        let bot = InboxThread.lastFrom ?? AssistantRoster.defaultBot(in: SettingsManager.shared.settings.assistantBots).name
        do {
            let replies = try await OwnAssistantService.shared.ask(
                transcript: text, cleaned: text, images: [], intent: "reply", targetBot: bot, replyTo: id
            )
            return replies.map { "\($0.fromBot): \($0.text)" }.joined(separator: " ")
        } catch {
            return error.localizedDescription
        }
    }

    func notePush(text: String, from: String, priority: String) {
        let line = "\(from): \(text)"
        statusLine = line
        switch priority {
        case "low":
            // Kept for later. A low alert never interrupts and is never spoken on arrival.
            GlassesMemory.remember("Later: \(line)")
            return
        case "urgent":
            TTSService.shared.stop()
        default:
            // A normal alert waits its turn. It is in the inbox list either way.
            if TTSService.shared.isSpeaking { return }
        }
        CompanionSurface.present(bot: from, text: text, kind: priority == "urgent" ? .alert : .reply) { spoken in
            TTSService.shared.speak("\(from): \(spoken)")
        }
    }

    private func takeOver(_ request: String) async -> String {
        let settings = SettingsManager.shared.settings
        guard settings.isOwnAssistantConfigured else {
            return "The relay is not configured, so I can't hand this to Fire Fox, Indy, Driver, and Rally."
        }
        let bots = AssistantRoster.normalized(settings.assistantBots)
        let names = bots.map(\.name)
        statusLine = "Asking \(names.joined(separator: ", ")) at the same time."
        refreshIsland()
        TTSService.shared.beginStreaming()
        TTSService.shared.speakChunk("Asking \(names.joined(separator: ", ")).")
        let heard = HeardPieces()
        await OwnAssistantService.shared.askEach(
            transcript: request, cleaned: request, intent: "takeover", bots: names
        ) { bot, text in
            let spoken = text.isEmpty ? "\(bot) did not answer." : "\(bot). \(text)"
            heard.lines.append(spoken)
            TaskLog.append(bot: bot, request: request, result: text.isEmpty ? "no answer" : text)
            self.statusLine = "\(bot) answered."
            TTSService.shared.speakChunk(spoken)
        }
        TTSService.shared.endStreaming()
        statusLine = "Listening for Jarvis. The mic indicator stays visible."
        refreshIsland()
        return heard.lines.isEmpty ? "No one answered." : ""
    }

    private func startWatch() {
        watchTask?.cancel()
        watchSends = 0
        cameraOn = true
        statusLine = "Camera on at 7 fps. The glasses light is on. I check faster when the scene changes."
        caption = ""
        refreshIsland()
        NotificationCenter.default.post(name: .phoenixKeepListening, object: nil)
        watchTask = Task {
            await GlassesManager.shared.startStreaming()
            var interval: UInt64 = 1_200_000_000
            var stable = 0
            var lastSent = Date.distantPast
            while !Task.isCancelled && cameraOn {
                try? await Task.sleep(nanoseconds: interval)
                guard let image = GlassesManager.shared.lastFrame,
                      let thumb = Thumbnail.bytes(image) else { continue }
                let delta = FrameChange.difference(lastThumb, thumb)
                let changed = !lastThumb.isEmpty && delta > FrameChange.sceneChangeThreshold && Date().timeIntervalSince(lastSent) > 4 && watchSends < 12
                lastThumb = thumb
                if changed {
                    stable = 0
                    interval = 400_000_000
                    lastSent = Date()
                    watchSends += 1
                    statusLine = "Scene changed. Camera light is on. Checking about twice a second."
                    refreshIsland()
                    guard let jpeg = ImageBudget.jpeg(image.jpegData(compressionQuality: 0.6)) else { continue }
                    if let sentence = try? await GrokService.shared.complete(
                        "One sentence: what changed?",
                        imageData: jpeg,
                        system: "Answer in one short spoken sentence."
                    ), !sentence.isEmpty {
                        caption = sentence
                        TranscriptLog.append("Watch: \(sentence)")
                        TTSService.shared.speakAmbient(sentence)
                    }
                } else {
                    stable += 1
                    if stable >= 3 { interval = 2_500_000_000 }
                    statusLine = "Watching. Camera light is on. The scene is steady, so I'm checking every couple of seconds."
                }
            }
            if GlassesManager.shared.isStreaming {
                await GlassesManager.shared.stopStreaming()
            }
        }
    }

    private func stopWatch() {
        watchTask?.cancel()
        watchTask = nil
        if SmartCapture.shared.isRunning {
            cameraOn = true
            statusLine = "Smart capture on. The glasses light is on."
            refreshIsland()
            return
        }
        cameraOn = false
        Task { await GlassesManager.shared.stopStreaming() }
        statusLine = "Listening for Jarvis. The mic indicator stays visible."
        refreshIsland()
    }

    private func refreshIsland() {
        let state = PhoenixActivityAttributes.ContentState(line: statusLine, cameraOn: cameraOn)
        let content = ActivityContent(state: state, staleDate: nil)
        // Each update waits for the one before it, so the island never shows an older line last.
        islandUpdate = Task { [previous = islandUpdate] in
            await previous?.value
            await Self.showIsland(content)
        }
    }

    private nonisolated static func showIsland(_ content: ActivityContent<PhoenixActivityAttributes.ContentState>) async {
        if let activity = Activity<PhoenixActivityAttributes>.activities.first {
            await activity.update(content)
        } else {
            _ = try? Activity.request(attributes: PhoenixActivityAttributes(title: "Phoenix Fox"), content: content, pushType: nil)
        }
    }

    private func translate(_ text: String) async -> String {
        guard SettingsManager.shared.settings.isGrokConfigured else {
            return "Translation needs the fast Grok key. I am not sending this to an unknown server."
        }
        do {
            let line = try await GrokService.shared.complete(
                text,
                imageData: nil,
                system: "Translate the user's words into \(translationTarget). Output only the translation, one or two sentences."
            )
            caption = line
            return line
        } catch {
            return "The translation didn't go through."
        }
    }

    private func summarizeMeeting() async -> String {
        let notes = TranscriptLog.recent()
        guard !notes.isEmpty else { return "There's no transcript yet. Say start translating or just talk after Jarvis." }
        guard SettingsManager.shared.settings.isOwnAssistantConfigured else {
            return "I saved the transcript on the phone. Add the relay if you want Fire Fox to summarize it."
        }
        do {
            let replies = try await OwnAssistantService.shared.ask(
                transcript: notes, cleaned: "Summarize these meeting notes in four short spoken sentences.",
                images: [], intent: "briefing", targetBot: "Fire Fox"
            )
            return replies.map(\.text).joined(separator: " ")
        } catch {
            return "I couldn't reach Fire Fox for the summary."
        }
    }

    private func morningBrief(force: Bool) async -> String {
        _ = force
        let reel = SmartCaptureIndex.reel()
        guard SettingsManager.shared.settings.isOwnAssistantConfigured else {
            return reel.isEmpty
                ? "Morning brief needs the relay. Fire Fox, Indy, Driver, and Rally aren't connected yet."
                : reel
        }
        do {
            let replies = try await OwnAssistantService.shared.ask(
                transcript: "morning brief", cleaned: "Give a short morning brief.",
                images: [], intent: "briefing", targetBot: "all"
            )
            let body = replies.map { "\($0.fromBot): \($0.text)" }.joined(separator: " ")
            return reel.isEmpty ? body : "\(reel) \(body)"
        } catch {
            return reel.isEmpty ? "The morning brief didn't come back." : reel
        }
    }
}

enum TranscriptLog {
    static func append(_ line: String) {
        let url = file()
        let row = ISO8601DateFormatter().string(from: Date()) + " " + line + "\n"
        if let data = row.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }

    static func recent() -> String {
        guard let text = try? String(contentsOf: file(), encoding: .utf8) else { return "" }
        return text.split(separator: "\n").suffix(40).joined(separator: "\n")
    }

    private static func file() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("phoenix-transcript.txt")
    }
}

enum TaskLog {
    static func append(bot: String, request: String, result: String) {
        var rows = load()
        rows.append(["bot": bot, "request": request, "result": result, "at": ISO8601DateFormatter().string(from: Date())])
        if rows.count > 40 { rows.removeFirst(rows.count - 40) }
        if let data = try? JSONSerialization.data(withJSONObject: rows) {
            try? data.write(to: file())
        }
    }

    static func lines() -> [String] {
        load().map { "\($0["at"] ?? "") \($0["bot"] ?? ""): \($0["result"] ?? "")" }
    }

    private static func load() -> [[String: String]] {
        guard let data = try? Data(contentsOf: file()),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return [] }
        return rows
    }

    private static func file() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("phoenix-tasks.json")
    }
}

enum SecureNotes {
    struct Item: Codable {
        var text: String
        var vector: [Double]
        var photo: Data?
    }

    static func remember(_ text: String, photo: Data? = nil) {
        var items = load()
        items.append(Item(text: text, vector: embed(text), photo: photo))
        if items.count > 80 { items.removeFirst(items.count - 80) }
        save(items)
    }

    static func search(_ query: String) -> String {
        let items = load()
        guard !items.isEmpty else { return "Nothing is stored yet." }
        let queryVector = embed(query)
        let best = items.max { cosine($0.vector, queryVector) < cosine($1.vector, queryVector) }
        guard let best else { return items.last?.text ?? "Nothing is stored yet." }
        return best.photo == nil ? best.text : "\(best.text) A photo is saved with that note."
    }

    static func entries() -> [Item] { load() }

    private static func embed(_ text: String) -> [Double] {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return [] }
        let words = text.lowercased().split(separator: " ").map(String.init)
        var sum: [Double] = []
        var count = 0
        for word in words {
            guard let vector = embedding.vector(for: word) else { continue }
            if sum.isEmpty { sum = vector }
            else if sum.count == vector.count {
                for index in sum.indices { sum[index] += vector[index] }
            }
            count += 1
        }
        guard count > 0 else { return [] }
        return sum.map { $0 / Double(count) }
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let na = sqrt(a.reduce(0) { $0 + $1 * $1 })
        let nb = sqrt(b.reduce(0) { $0 + $1 * $1 })
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na * nb)
    }

    private static func key() -> SymmetricKey {
        let account = "phoenix.memory.key"
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
            .appendingPathComponent("phoenix-memory.enc")
    }

    private static func load() -> [Item] {
        guard let sealed = try? Data(contentsOf: file()),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let clear = try? AES.GCM.open(box, using: key()) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: clear)) ?? []
    }

    private static func save(_ items: [Item]) {
        guard let clear = try? JSONEncoder().encode(items),
              let box = try? AES.GCM.seal(clear, using: key()),
              let combined = box.combined else { return }
        try? combined.write(to: file())
    }
}

enum Thumbnail {
    static func bytes(_ image: UIImage) -> [UInt8]? {
        let size = CGSize(width: 24, height: 24)
        let renderer = UIGraphicsImageRenderer(size: size)
        let small = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let cg = small.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: 24 * 24)
        guard let context = CGContext(
            data: &pixels, width: 24, height: 24, bitsPerComponent: 8, bytesPerRow: 24,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 24, height: 24))
        return pixels
    }
}

/// Set when the Jarvis shortcut launched the app, so the voice screen starts listening at once.
@MainActor
enum JarvisWake {
    static var pending = false
}

struct JarvisWakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Jarvis"
    static let description = IntentDescription("Wake Phoenix Fox. Jarvis is the spoken name, not the app name.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        JarvisWake.pending = true
        NotificationCenter.default.post(name: .phoenixWake, object: nil)
        return .result()
    }
}

struct PhoenixShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: JarvisWakeIntent(),
            phrases: ["Wake Jarvis in \(.applicationName)", "Start Jarvis in \(.applicationName)"],
            shortTitle: "Jarvis",
            systemImageName: "waveform"
        )
    }
}

struct PhoenixActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var line: String
        var cameraOn: Bool
    }
    var title: String
}

extension Notification.Name {
    static let phoenixWake = Notification.Name("phoenix.wake")
    static let phoenixRecord = Notification.Name("phoenix.record")
    static let phoenixStopRecord = Notification.Name("phoenix.stopRecord")
    static let phoenixKeepListening = Notification.Name("phoenix.keepListening")
}

/// Collects parallel bot replies without capturing a mutating local from an escaping closure.
final class HeardPieces {
    var lines: [String] = []
}

/// Arms a circular region after the wearer asks. The system location arrow stays visible.
///
/// Main actor: the location manager is created here and calls its delegate back here.
@MainActor
final class PlaceReminders: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = PlaceReminders()
    private let manager = CLLocationManager()
    private let defaultsKey = "phoenix.geofence.notes"

    private override init() {
        super.init()
        manager.delegate = self
    }

    func arm(_ utterance: String) async -> String {
        guard let parsed = Self.parse(utterance) else {
            return "Say when I arrive at a place, then what to remember. Example: when I arrive at the office, remind me to call Sam."
        }
        manager.requestAlwaysAuthorization()
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            return "Geofenced reminders need location permission. iOS shows the location arrow. Allow it, then say the place again. I have not started watching."
        }
        guard let place = await Self.locate(parsed.place) else {
            return "I couldn't find \(parsed.place), so I didn't arm a reminder."
        }
        let id = UUID().uuidString
        var notes = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        notes[id] = parsed.note
        UserDefaults.standard.set(notes, forKey: defaultsKey)
        let center = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let region = CLCircularRegion(center: center, radius: 150, identifier: id)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        manager.startMonitoring(for: region)
        let scope = status == .authorizedAlways ? "including in the background" : "while Phoenix Fox is open. Allow Always if you want it after you leave the app"
        return "I'll remind you to \(parsed.note) when you arrive at \(place.name ?? parsed.place), \(scope). The location arrow stays on."
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        let notes = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        let note = notes[id] ?? "You arrived."
        TTSService.shared.speak(note)
        Task {
            let content = UNMutableNotificationContent()
            content.title = "Phoenix Fox"
            content.body = note
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: id, content: content, trigger: nil)
            )
        }
    }

    /// Looks the place up off the main actor and brings back only plain values.
    private nonisolated static func locate(_ query: String) async -> PlaceFix? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        return PlaceFix(latitude: coordinate.latitude, longitude: coordinate.longitude, name: item.name)
    }

    private static func parse(_ utterance: String) -> (place: String, note: String)? {
        let lower = utterance.lowercased()
        let markers = ["when i arrive at ", "when i get to "]
        guard let marker = markers.first(where: { lower.contains($0) }),
              let range = lower.range(of: marker) else { return nil }
        let rest = String(utterance[range.upperBound...])
        let restLower = rest.lowercased()
        if let cut = restLower.range(of: " remind me to ") ?? restLower.range(of: ", ") {
            let place = String(rest[..<cut.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            var note = String(rest[cut.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if note.lowercased().hasPrefix("remind me to ") {
                note = String(note.dropFirst("remind me to ".count))
            }
            guard !place.isEmpty, !note.isEmpty else { return nil }
            return (place, note)
        }
        return nil
    }
}

/// Receives the APNs device token and a silent push. Delivery still depends on Apple's push
/// capability and a key the owner has not added. The inbox long-poll is the path that works without it.
final class PhoenixPushDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Unit tests run inside this app. They must not register a device with Apple.
        guard !AppLaunch.isHostingTests else { return true }
        // Renews the registration if alerts are already allowed. Asking happens in Settings.
        Task { await PushAlerts.refresh(askIfNeeded: false) }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02hhx", $0) }.joined()
        Task { await OwnAssistantService.shared.registerDevice(hex) }
    }

    /// Without a token there are no pushes. The inbox still delivers while the app is open,
    /// and the reason is kept in the glasses log so it can be read on the phone.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        let reason = error.localizedDescription
        Task { @MainActor in
            GlassesLink.shared.record("Apple did not give this phone a push token: \(reason)")
        }
    }

    /// A silent push only says "something is waiting". The message itself is pulled from the
    /// relay inbox, so nothing private travels through the push payload.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            await OwnAssistantService.shared.pullInboxOnce()
            completionHandler(.newData)
        }
    }
}

struct PhoenixLogView: View {
    var body: some View {
        List {
            Section("Take over") {
                let lines = TaskLog.lines()
                if lines.isEmpty {
                    Text("Nothing yet. Say Grok, take over, and the four replies land here.")
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.callout)
                    }
                }
            }
            Section("Encrypted notes") {
                let notes = SecureNotes.entries()
                if notes.isEmpty {
                    Text("Say remember this. Notes are encrypted on the phone.")
                } else {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.text)
                            if let photo = note.photo, let image = UIImage(data: photo) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 120)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Task history")
    }
}
