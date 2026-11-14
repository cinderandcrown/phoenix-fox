// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Wearer opt-in before face recognition turns on (Texas CUBI / Illinois BIPA notice).
// Per-person enrollment still requires that person's spoken yes (AccessFaces / coordinator).

import Foundation

enum FaceRecognitionConsent {
    static let defaultsKey = "ov.faceRecognition.wearerNoticeAcceptedAt"

    static let noticeTitle = "Face recognition on this iPhone"

    /// Plain-language explainer for Settings (CUBI / BIPA). Keep in sync with docs/legal/FACE_RETENTION.md.
    static let noticeBody = """
    Face recognition saves a numeric face print — not a photo — for people you enroll. Prints stay on this iPhone, are encrypted, are not in iCloud backups, and are never sent to the cloud or to \(PublisherIdentity.legalName).

    This is biometric data. Under Texas law (CUBI) and Illinois law (BIPA), biometric identifiers need informed consent before they are collected. You must only enroll someone after that person agrees out loud. Phoenix Fox asks them to say yes, and keeps the time of that yes with their print.

    Unenrolled faces (strangers) are never stored. Prints delete automatically after 30 days with no match (you can shorten that to as little as 1 day), or right away when you say forget this person / forget everyone, or Delete in Settings.

    Face recognition stays off until you Allow below. You can turn it off anytime.
    """

    static let spokenOptInPrompt = """
    Face recognition stores biometric face prints on this phone only. Under Texas and Illinois law, each person must agree out loud before I save them. Strangers are never stored. Prints delete after thirty days with no match, or when you say forget. Say yes to turn face recognition on, or no to leave it off.
    """

    static let enrollmentConsentPrompt: (String) -> String = { name in
        "\(name), say yes if you agree I may save your face print on this iPhone for recognition. This is biometric data under Texas and Illinois law. Say no if you do not agree."
    }

    static func isWearerNoticeAccepted(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) != nil
    }

    static func acceptedAt(defaults: UserDefaults = .standard) -> Date? {
        guard let raw = defaults.object(forKey: defaultsKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    static func acceptWearerNotice(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now.timeIntervalSince1970, forKey: defaultsKey)
    }

    static func withdrawWearerNotice(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Clamps retention to 1…30 days (Nicholas: configurable down to 1 day; default 30).
    static func clampedRetentionDays(_ days: Int) -> Int {
        min(30, max(1, days))
    }
}
