// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Phoenix Fox local features that match Meta AI where iOS and DAT allow it.
// Anything this file cannot do is spoken as blocked. It never pretends a call,
// a WhatsApp video session, or an in-lens map succeeded.

import AVFoundation
import Contacts
import Foundation
import MapKit
import MediaPlayer
import Photos
import UIKit
import Vision

@MainActor
enum PhoenixFoxFeatures {
    enum Outcome {
        case spoken(String)
        /// Take one photo and answer with the cheap vision path.
        case look(String)
    }

    static func handle(_ text: String, snapshot: () async -> Data?) async -> Outcome? {
        let lower = text.lowercased()
        if isDisplayOnly(lower) && !GlassesLink.shared.displayCapable {
            return .spoken("That needs Meta Ray-Ban Display. These glasses have no lens screen, so I will keep answering out loud.")
        }
        if lower.contains("be my eyes") || lower.contains("call a volunteer") {
            return .spoken("A Be My Eyes volunteer can only see your camera from inside the Meta AI app. I can describe the scene instead. Say look at this.")
        }
        if lower.contains("whatsapp") || lower.contains("messenger") || (lower.contains("instagram") && (lower.contains("call") || lower.contains("video"))) {
            if lower.contains("call") || lower.contains("video") {
                return .spoken("WhatsApp, Messenger, and Instagram calls stay inside those apps. Meta does not let another app place them from the glasses. I can open a chat with your words filled in, or call a phone number.")
            }
        }
        if lower.contains("whatsapp") || lower.contains("on messenger") || lower.hasPrefix("email ") || lower.hasPrefix("send an email") {
            return .spoken(await MessageHandoff.send(text))
        }
        if lower.contains("live translation") || lower.contains("translate this conversation") {
            return .spoken("I can translate the next thing you say, or a sign if you say look at this. A continuous two-person interpreter with captions is a Meta AI and Display feature, and these glasses have no lens screen.")
        }
        if lower.contains("read my notifications") || lower.contains("read my messages") || lower.contains("what notifications") {
            return .spoken("iOS does not let Phoenix Fox read WhatsApp, Messenger, or text notifications. I only hear reminders and timers that I set.")
        }
        if contains(lower, ["what time", "what's the time", "what is the time"]) {
            return .spoken("It's \(Self.time.string(from: Date())).")
        }
        if contains(lower, ["what's the date", "what is the date", "what's today's date"]) {
            return .spoken(Self.day.string(from: Date()))
        }
        if contains(lower, ["battery", "how much charge", "battery left"]) {
            if let level = GlassesLink.shared.battery {
                let charge = GlassesLink.shared.charging ? " Charging." : ""
                return .spoken("The glasses are at \(level) percent.\(charge)")
            }
            return .spoken("I can't see the glasses battery yet. Connect them first.")
        }
        if let seconds = timerSeconds(in: lower) {
            let spoken = (try? await TimerTool().execute(args: ["seconds": JSONValue(seconds)])) ?? "I couldn't set the timer."
            return .spoken(spoken)
        }
        if lower.hasPrefix("remind me") {
            let title = text.replacingOccurrences(of: "remind me to ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "remind me ", with: "", options: .caseInsensitive)
            let spoken = (try? await ReminderTool().execute(args: ["title": JSONValue(title)])) ?? "I couldn't save the reminder."
            return .spoken(spoken)
        }
        if lower.hasPrefix("remember ") || lower.hasPrefix("remember this") {
            let photo = await snapshot()
            GlassesMemory.remember(text, photo: photo)
            return .spoken(photo == nil
                ? "Remembered on this phone, encrypted."
                : "Remembered, with a photo. The camera light was on for that shot.")
        }
        if contains(lower, ["what do you remember", "what did i ask you to remember", "search my memory", "what did i tell you to remember", "where did i park", "where did i leave"]) {
            return .spoken(GlassesMemory.recall(matching: text))
        }
        let command = lower.trimmingCharacters(in: .punctuationCharacters)
        if ["pause", "pause music", "pause the music"].contains(command) {
            MPMusicPlayerController.systemMusicPlayer.pause()
            return .spoken("Paused the phone's music player. Spotify and others only pause if they are the system player.")
        }
        if ["play", "play the music", "resume", "resume the music"].contains(command) {
            MPMusicPlayerController.systemMusicPlayer.play()
            return .spoken("Playing on the phone's music player.")
        }
        if hasCommand(lower, ["next track", "next song", "skip the song", "skip this song", "skip track"]) {
            MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
            return .spoken("Next track.")
        }
        if hasCommand(lower, ["previous track", "previous song", "last song"]) {
            MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem()
            return .spoken("Previous track.")
        }
        if lower.contains("volume") {
            let value = Int(AVAudioSession.sharedInstance().outputVolume * 100)
            return .spoken("Volume is about \(value) percent. The glasses rocker still changes it. iOS does not let an app set the volume.")
        }
        if lower.contains("take a video") || lower.contains("start a video") || lower.contains("record a video") {
            return .spoken("Say record a clip. I record the preview while the glasses light is on, and I won't pretend it's Meta's 3K file.")
        }
        if contains(lower, ["take a picture", "take a photo", "take photo"]) {
            guard let data = await snapshot() else { return .spoken("I couldn't get a photo from the glasses.") }
            let saved = await savePhoto(data)
            return .spoken(saved ? "Picture saved on your phone." : "I took the picture but couldn't save it to Photos.")
        }
        if lower.contains("qr") || lower.contains("barcode") {
            guard let data = await snapshot() else { return .spoken("I couldn't see a code.") }
            return .spoken(await readCode(in: data))
        }
        if lower.hasPrefix("navigate") || lower.hasPrefix("directions to") || lower.hasPrefix("take me to") {
            let place = text.replacingOccurrences(of: "navigate me to ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "navigate to ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "directions to ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "take me to ", with: "", options: .caseInsensitive)
            return .spoken(await directions(to: place))
        }
        if lower.hasPrefix("call ") {
            return .spoken(await call(String(text.dropFirst(5))))
        }
        if lower.hasPrefix("text ") || lower.hasPrefix("send a message") || lower.hasPrefix("message ") {
            return .spoken(await message(text))
        }
        return nil
    }

    private static func isDisplayOnly(_ lower: String) -> Bool {
        contains(lower, ["show me the map", "in the lens", "on the display", "captions on the lens", "neural band"])
    }

    private static func hasCommand(_ text: String, _ phrases: [String]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .punctuationCharacters)
        return phrases.contains { trimmed == $0 || trimmed.hasPrefix($0 + " ") }
    }

    private static func contains(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func timerSeconds(in lower: String) -> Int? {
        guard lower.contains("timer") else { return nil }
        let pattern = #"(\d+)\s*(second|minute|hour)"#
        guard let match = lower.range(of: pattern, options: .regularExpression) else { return nil }
        let piece = String(lower[match])
        let number = Int(piece.prefix { $0.isNumber }) ?? 0
        if piece.contains("hour") { return number * 3600 }
        if piece.contains("minute") { return number * 60 }
        return number
    }

    private static func savePhoto(_ data: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }

    private static func readCode(in data: Data) async -> String {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr, .ean13, .code128]
        let handler = VNImageRequestHandler(data: data)
        guard (try? handler.perform([request])) != nil,
              let code = request.results?.first?.payloadStringValue, !code.isEmpty else {
            return "I didn't see a QR code in that shot."
        }
        if let url = URL(string: code), url.scheme == "https" || url.scheme == "http" {
            await UIApplication.shared.open(url)
            return "Opened \(code)."
        }
        return "The code says \(code)."
    }

    private static func directions(to place: String) async -> String {
        let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Where should I send you?" }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let response = try? await MKLocalSearch(request: request).start()
        guard let item = response?.mapItems.first else {
            return "I couldn't find \(trimmed)."
        }
        let destination = item.placemark.coordinate
        let dir = MKDirections.Request()
        dir.source = MKMapItem.forCurrentLocation()
        dir.destination = item
        dir.transportType = .walking
        let route = try? await MKDirections(request: dir).calculate()
        let first = route?.routes.first
        if let url = URL(string: "http://maps.apple.com/?daddr=\(destination.latitude),\(destination.longitude)&dirflg=w") {
            await UIApplication.shared.open(url)
        }
        if let step = first?.steps.first(where: { !$0.instructions.isEmpty }) {
            let miles = (first?.distance ?? 0) / 1609
            return "Walking about \(String(format: "%.1f", miles)) miles. First, \(step.instructions). I opened Apple Maps. I can't keep a Meta-style guidance session running in the glasses."
        }
        return "I opened walking directions to \(item.name ?? trimmed) in Apple Maps."
    }

    private static func call(_ who: String) async -> String {
        let target = who.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = phoneDigits(in: target) {
            if let url = URL(string: "tel:\(number)") { await UIApplication.shared.open(url) }
            return "Calling \(number)."
        }
        guard let number = await contactNumber(matching: target) else {
            return "I couldn't find a phone number for \(target). Meta's app uses its own contact link. I can call a number you say."
        }
        if let url = URL(string: "tel:\(number)") { await UIApplication.shared.open(url) }
        return "Calling \(target)."
    }

    private static func message(_ text: String) async -> String {
        await MessageHandoff.send(text)
    }

    static func contactNumber(matching name: String) async -> String? {
        let store = CNContactStore()
        let granted = await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
        guard granted else { return nil }
        let predicate = CNContact.predicateForContacts(matchingName: name)
        let keys = [CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let found = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
        return found.first?.phoneNumbers.first?.value.stringValue.filter { $0.isNumber || $0 == "+" }
    }

    private static func phoneDigits(in text: String) -> String? {
        let digits = text.filter { $0.isNumber || $0 == "+" }
        return digits.count >= 7 ? digits : nil
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()
}

enum GlassesMemory {
    static func remember(_ text: String, photo: Data? = nil) {
        if let legacy = legacyItems() {
            for item in legacy { SecureNotes.remember(item) }
            try? FileManager.default.removeItem(at: legacyFile())
        }
        SecureNotes.remember(text, photo: photo)
    }

    static func recall(matching query: String) -> String {
        if let legacy = legacyItems() {
            for item in legacy { SecureNotes.remember(item) }
            try? FileManager.default.removeItem(at: legacyFile())
        }
        return SecureNotes.search(query)
    }

    private static func legacyFile() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("phoenix-memory.json")
    }

    private static func legacyItems() -> [String]? {
        guard let data = try? Data(contentsOf: legacyFile()),
              let rows = try? JSONDecoder().decode([Legacy].self, from: data) else { return nil }
        return rows.map(\.text)
    }

    private struct Legacy: Codable { var text: String; var at: Date }
}
