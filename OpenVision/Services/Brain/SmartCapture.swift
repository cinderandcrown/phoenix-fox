// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Smart Capture. The glasses stream stays on, so the hardware light stays on.
// On-device scoring decides which frames are worth a Grok call. Grok keeps or
// skips, and a kept frame goes to the Phoenix Fox album plus an encrypted index.

import Contacts
import CryptoKit
import Foundation
import Photos
import SwiftUI
import UIKit

@MainActor
final class SmartCapture: ObservableObject {
    static let shared = SmartCapture()

    @Published private(set) var isRunning = false
    private var task: Task<Void, Never>?
    private var startedAt = Date()
    private var grokCalls = 0
    private var kept = 0
    private var announcedCap = false

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
        guard SettingsManager.shared.settings.isGrokConfigured else {
            return "Smart capture needs the Grok key. I didn't turn the camera on."
        }
        guard GlassesManager.shared.isRegistered else {
            return "Connect the glasses first. Smart capture uses their camera, and the light stays on."
        }
        isRunning = true
        startedAt = Date()
        grokCalls = 0
        kept = 0
        announcedCap = false
        let minutes = max(SettingsManager.shared.settings.smartCaptureMinutes, 1)
        CompanionRuntime.shared.showCamera(on: true, line: "Smart capture on. The glasses light is on.")
        NotificationCenter.default.post(name: .phoenixKeepListening, object: nil)
        task = Task { await self.loop() }
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
        await GlassesManager.shared.startStreaming()
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
            if grokCalls >= max(settings.smartCaptureCostCap, 1) {
                if !announcedCap {
                    announcedCap = true
                    TTSService.shared.speakAmbient("The capture cost cap is reached. I won't send more frames. The light stays on until you stop it or the timer ends.")
                }
                continue
            }
            lastSent = Date()
            grokCalls += 1
            guard let jpeg = ImageBudget.jpeg(image.jpegData(compressionQuality: 0.55)) else { continue }
            await judge(jpeg, settings: settings)
        }
    }

    private func judge(_ jpeg: Data, settings: AppSettings) async {
        let categories = enabledCategories(settings)
        guard !categories.isEmpty else { return }
        let system = """
        You judge one glasses frame for Smart Capture. Reply with JSON only, no markdown:
        {"keep":false,"tags":[],"caption":"","action":"none","contact":{"name":"","phone":"","email":""}}
        keep is true only for a clear \(categories.joined(separator: ", ")).
        action is one of receipt, card, whiteboard, highlight, none.
        caption is one short spoken sentence. contact is filled only for a business card.
        """
        guard let raw = try? await GrokService.shared.complete("Judge this frame.", imageData: jpeg, system: system),
              let verdict = CaptureVerdict.parse(raw),
              verdict.keep,
              enabled(verdict.action, settings: settings) else { return }
        let saved = await PhoenixAlbum.saveJPEG(jpeg)
        guard saved else {
            TTSService.shared.speakAmbient("I wanted to keep that frame, but Photos didn't take it.")
            return
        }
        let caption = verdict.caption.isEmpty ? "Kept a \(verdict.action)." : verdict.caption
        SmartCaptureIndex.remember(CaptureItem(
            caption: caption,
            tags: verdict.tags,
            action: verdict.action,
            at: Date(),
            highlight: verdict.action == "highlight"
        ))
        kept += 1
        CompanionRuntime.shared.caption = caption
        var spoken = caption
        if settings.smartCaptureAutoRoute {
            spoken += " " + route(verdict)
        }
        TTSService.shared.speakAmbient(spoken)
    }

    private func route(_ verdict: CaptureVerdict) -> String {
        switch verdict.action {
        case "receipt":
            let caption = verdict.caption
            Task {
                _ = try? await OwnAssistantService.shared.ask(
                    transcript: caption,
                    cleaned: "A receipt was captured: \(caption)",
                    images: [],
                    intent: "capture",
                    targetBot: "Fire Fox"
                )
            }
            return "Sending it to Fire Fox."
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
        if GlassesManager.shared.isStreaming {
            await GlassesManager.shared.stopStreaming()
        }
        CompanionRuntime.shared.showCamera(on: false, line: "Listening for Jarvis. The mic indicator stays visible.")
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

enum PhoenixAlbum {
    static func saveJPEG(_ data: Data) async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let granted = current == .notDetermined ? await PHPhotoLibrary.requestAuthorization(for: .readWrite) : current
        guard granted == .authorized || granted == .limited else { return false }
        let existing = album()
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
                guard let placeholder = request.placeholderForCreatedAsset else { return }
                let assets = [placeholder] as NSArray
                if let existing, let change = PHAssetCollectionChangeRequest(for: existing) {
                    change.addAssets(assets)
                } else {
                    let created = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "Phoenix Fox")
                    created.addAssets(assets)
                }
            } completionHandler: { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }

    private static func album() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", "Phoenix Fox")
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
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
            Section("Session") {
                Stepper("Minutes: \(settings.settings.smartCaptureMinutes)", value: $settings.settings.smartCaptureMinutes, in: 5...120, step: 5)
                Stepper("Max captures: \(settings.settings.smartCaptureMax)", value: $settings.settings.smartCaptureMax, in: 1...50)
                Stepper("Grok calls: \(settings.settings.smartCaptureCostCap)", value: $settings.settings.smartCaptureCostCap, in: 1...40)
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
                Toggle("Send kept items to the relay", isOn: $settings.settings.smartCaptureAutoRoute)
            } header: {
                Text("Categories")
            } footer: {
                Text("Receipts can go to Fire Fox, cards to Contacts, whiteboards to notes, and highlights into the morning brief. Auto-route stays off until you turn it on.")
            }
        }
        .navigationTitle("Smart Capture")
    }
}
