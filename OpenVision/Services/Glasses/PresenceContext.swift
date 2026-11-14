// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Shared worn / posture / walk-inbox / resume state driven by DAT motion + don state.
// Features (Walk my inbox, Pick up where I left off, confirmations) read and write here
// instead of each owning a private IMU listener.

import Foundation

@MainActor
final class PresenceContext: ObservableObject {
    static let shared = PresenceContext()

    @Published private(set) var posture = WornPostureContext(
        worn: false,
        posture: .unknown,
        pitchDegrees: nil,
        updatedAt: 0
    )
    @Published private(set) var lastResumeOffer: SessionResumeStore.Snapshot?

    private var tracker = WornPostureTracker()
    private var resume = SessionResumeStore()
    private(set) var inboxWalk = InboxWalkController()

    private init() {}

    var headAnswerPolicy: HeadAnswerPolicy {
        if inboxWalk.headAnswerPolicy != .none { return inboxWalk.headAnswerPolicy }
        return .none
    }

    func noteWorn(_ worn: Bool) {
        tracker.setWorn(worn)
        if !worn {
            posture = WornPostureContext(worn: false, posture: .unknown, pitchDegrees: nil, updatedAt: posture.updatedAt)
        }
    }

    /// Called from the motion sample loop (may hop to MainActor).
    func ingestMotion(_ sample: HeadMotion, worn: Bool) {
        noteWorn(worn)
        guard let context = tracker.take(sample, worn: worn) else { return }
        posture = context
        if let offer = resume.offer(on: context) {
            lastResumeOffer = offer
            NotificationCenter.default.post(name: .jarvisSessionResume, object: offer.title)
        }
    }

    func rememberForResume(title: String, detail: String) {
        resume.remember(title: title, detail: detail, at: Date().timeIntervalSince1970)
    }

    func clearResumeOffer() {
        lastResumeOffer = nil
        resume.clear()
    }

    func startInboxWalk(_ items: [InboxWalkItem]) {
        inboxWalk.start(items)
    }

    func stopInboxWalk() {
        inboxWalk.stop()
    }

    /// Returns an act/skip pair when the walk claims this head answer.
    func takeInboxAnswer(_ answer: HeadAnswer) -> (item: InboxWalkItem, action: InboxWalkAction)? {
        inboxWalk.take(answer)
    }
}

extension Notification.Name {
    /// Posted when donning + level posture unlocks a saved activity. Object is the title.
    static let jarvisSessionResume = Notification.Name("jarvis.sessionResume")
}
