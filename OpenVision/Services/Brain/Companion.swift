// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Hands-free companion actions that stay on public APIs.
// The glasses capture light is the hardware's. This file never turns it off
// and never starts the camera without a spoken request.

import ActivityKit
import AppIntents
import AVFoundation
import Contacts
import CryptoKit
import Foundation
import NaturalLanguage
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
                let rest = String(utterance[range.upperBound...])
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
    @Published var statusLine = "Listening for Jarvis. The mic dot stays visible."

    private var watchTask: Task<Void, Never>?
    private var lastThumb: [UInt8] = []
    private var watchSends = 0
    private var translating = false

    private init() {}

    /// Returns a spoken line when this command is handled here.
    func consume(_ text: String, snapshot: () async -> Data?) async -> String? {
        let lower = text.lowercased()
        if lower.contains("take over") || lower.hasPrefix("grok, take over") || lower.hasPrefix("grok take over") {
            return await takeOver(text)
        }
        if lower.contains("watch this") || lower.contains("start watching") {
            startWatch()
            return "Watching. The glasses camera light is on. I only send a frame when the scene changes. Say stop watching."
        }
        if lower.contains("stop watching") {
            stopWatch()
            return "Stopped watching. The camera is off."
        }
        if lower.contains("record a clip") || lower.contains("start recording") {
            NotificationCenter.default.post(name: .phoenixRecord, object: nil)
            cameraOn = true
            statusLine = "Recording. The glasses camera light is on."
            return "Recording. The glasses light stays on while the camera is open. Say stop recording."
        }
        if lower.contains("stop recording") {
            NotificationCenter.default.post(name: .phoenixStopRecord, object: nil)
            cameraOn = false
            statusLine = "Listening for Jarvis. The mic dot stays visible."
            return "Stopped. The clip saves to Photos if the recorder finished."
        }
        if lower.contains("translate to ") || lower == "start translating" {
            translating = true
            TranscriptLog.append("Translation on: \(text)")
            return "I'll translate the next things you say into your ear. Captions are saved on the phone. Say stop translating."
        }
        if lower.contains("stop translating") {
            translating = false
            return "Translation off."
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
            return "Geofenced reminders need Always location, which shows the system location arrow. Say the place again after you allow it in Settings. I will not watch location in the background until you do."
        }
        return nil
    }

    func maybeMorningBrief() async {
        let hour = Calendar.current.component(.hour, from: Date())
        guard (5..<11).contains(hour) else { return }
        let key = "phoenix.morning.\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        _ = await morningBrief(force: true)
    }

    func notePush(text: String, from: String, priority: String) {
        let line = "\(from): \(text)"
        if priority == "urgent" {
            TTSService.shared.stop()
            TTSService.shared.speak(line)
        } else if priority == "low" {
            GlassesMemory.remember("Later: \(line)")
        } else if !TTSService.shared.isSpeaking {
            TTSService.shared.speak(line)
        }
        statusLine = line
    }

    private func takeOver(_ request: String) async -> String {
        let settings = SettingsManager.shared.settings
        guard settings.isOwnAssistantConfigured else {
            return "The relay is not configured, so I can't hand this to Fire Fox, Indy, Driver, and Rally."
        }
        let bots = AssistantRoster.normalized(settings.assistantBots)
        statusLine = "Asking \(bots.map(\.name).joined(separator: ", "))."
        var pieces: [String] = []
        for bot in bots {
            do {
                let replies = try await OwnAssistantService.shared.ask(
                    transcript: request, cleaned: request, images: [], intent: "takeover", targetBot: bot.name
                )
                let text = replies.map(\.text).joined(separator: " ")
                pieces.append("\(bot.name): \(text)")
                TaskLog.append(bot: bot.name, request: request, result: text)
            } catch {
                pieces.append("\(bot.name) did not answer.")
            }
        }
        let summary = pieces.joined(separator: " ")
        statusLine = "Listening for Jarvis. The mic dot stays visible."
        refreshIsland()
        return summary.isEmpty ? "No one answered." : summary
    }

    private func startWatch() {
        watchTask?.cancel()
        watchSends = 0
        cameraOn = true
        statusLine = "Camera on. The glasses light is on. Sending only when the scene changes."
        watchTask = Task {
            await GlassesManager.shared.startStreaming()
            var lastSent = Date.distantPast
            while !Task.isCancelled && cameraOn {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let image = GlassesManager.shared.lastFrame,
                      let thumb = Thumbnail.bytes(image) else { continue }
                let delta = FrameChange.difference(lastThumb, thumb)
                lastThumb = thumb
                guard delta > 0.08, Date().timeIntervalSince(lastSent) > 4, watchSends < 12 else { continue }
                lastSent = Date()
                watchSends += 1
                guard let jpeg = ImageBudget.jpeg(image.jpegData(compressionQuality: 0.6)) else { continue }
                if SettingsManager.shared.settings.isGrokConfigured {
                    try? await GrokService.shared.sendMessage("One sentence: what changed?", imageData: jpeg, system: "Answer in one short spoken sentence.")
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
        cameraOn = false
        Task { await GlassesManager.shared.stopStreaming() }
        statusLine = "Listening for Jarvis. The mic dot stays visible."
        refreshIsland()
    }

    private func refreshIsland() {
        let state = PhoenixActivityAttributes.ContentState(line: statusLine, cameraOn: cameraOn)
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = Activity<PhoenixActivityAttributes>.activities.first {
            Task { await activity.update(content) }
        } else {
            _ = try? Activity.request(attributes: PhoenixActivityAttributes(title: "Phoenix Fox"), content: content, pushType: nil)
        }
    }

    private func translate(_ text: String) async -> String {
        guard SettingsManager.shared.settings.isGrokConfigured else {
            return "Translation needs the fast Grok key, or say take over and the relay will translate. I am not sending this to an unknown server."
        }
        do {
            try await GrokService.shared.sendMessage(text, imageData: nil, system: "Translate the user's words into clear English. Output only the translation, one or two sentences.")
            return "Translated."
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
        guard SettingsManager.shared.settings.isOwnAssistantConfigured else {
            return "Morning brief needs the relay. Fire Fox, Indy, Driver, and Rally aren't connected yet."
        }
        _ = force
        do {
            let replies = try await OwnAssistantService.shared.ask(
                transcript: "morning brief", cleaned: "Give a short morning brief.",
                images: [], intent: "briefing", targetBot: "all"
            )
            return replies.map { "\($0.fromBot): \($0.text)" }.joined(separator: " ")
        } catch {
            return "The morning brief didn't come back."
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
        guard let text = try? String(contentsOf: file()) else { return "" }
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
    private struct Item: Codable { var text: String; var vector: [Double] }

    static func remember(_ text: String) {
        var items = load()
        items.append(Item(text: text, vector: embed(text)))
        if items.count > 80 { items.removeFirst(items.count - 80) }
        save(items)
    }

    static func search(_ query: String) -> String {
        let items = load()
        guard !items.isEmpty else { return "Nothing is stored yet." }
        let queryVector = embed(query)
        let best = items.max { cosine($0.vector, queryVector) < cosine($1.vector, queryVector) }
        return best?.text ?? items.last!.text
    }

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

struct JarvisWakeIntent: AppIntent {
    static var title: LocalizedStringResource = "Jarvis"
    static var description = IntentDescription("Wake Phoenix Fox. Jarvis is the spoken name, not the app name.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .phoenixWake, object: nil)
        }
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
}
