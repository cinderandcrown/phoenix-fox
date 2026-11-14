// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI

/// The home screen, drawn from a `HomeModel`.
///
/// From the top: the glasses, what Jarvis is doing, what was just said, and the team.
/// It scrolls, so nothing is cut off at the largest text sizes.
struct HomeContent: View {
    let model: HomeModel
    var actions = HomeActions()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.roomy) {
                HomeHeader(
                    glasses: model.glasses,
                    canRecord: model.canRecord,
                    isRecording: model.isRecording,
                    onGlasses: actions.glasses,
                    onRecord: actions.record
                )

                LiveStage(phase: model.phase, signals: model.signals, fixedTime: model.fixedTime, onTap: actions.stage)

                VStack(spacing: Theme.Space.snug) {
                    if model.signals.cameraOn {
                        CameraBanner()
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    if let note = model.recordingNote {
                        NoteRow(symbol: "record.circle", text: note)
                            .transition(.opacity)
                    }
                    if let document = model.document {
                        DocumentRow(title: document, onClose: actions.closeDocument)
                            .transition(.opacity)
                    }
                    if !model.status.isEmpty || !model.caption.isEmpty {
                        CaptionCard(status: model.status, caption: model.caption, large: model.largeCaption)
                            .transition(.opacity)
                    }
                    if model.showsExchange, !model.heard.isEmpty || !model.reply.isEmpty {
                        ExchangeCard(heard: model.heard, reply: model.reply)
                            .transition(.opacity)
                    }
                }

                switch model.team {
                case .members(let members):
                    TeamSection(members: members, now: model.now, wakeWord: model.signals.wakeWord)
                case .connect:
                    ConnectCard(onConnect: actions.connectAssistants)
                case .brain(let name):
                    BrainCard(name: name, onChoose: actions.chooseBrain)
                }
            }
            .padding(.horizontal, Theme.Space.normal)
            .padding(.top, Theme.Space.tight)
            .padding(.bottom, Theme.Space.wide)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(HomeBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let trouble = model.trouble {
                TroubleBanner(message: trouble, onDismiss: actions.dismissTrouble)
                    .padding(Theme.Space.normal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.state, value: model.signals.cameraOn)
        .animation(Theme.Motion.state, value: model.trouble)
        .animation(Theme.Motion.state, value: model.document)
        .animation(Theme.Motion.state, value: model.recordingNote)
        .animation(Theme.Motion.state, value: model.heard.isEmpty && model.reply.isEmpty)
    }
}

/// Warm parchment by day and warm black by night, with heat rising from the top.
struct HomeBackdrop: View {
    var body: some View {
        ZStack {
            Theme.canvas
            RadialGradient(
                colors: [Theme.ember.opacity(0.16), Theme.ember.opacity(0)],
                center: .top, startRadius: 0, endRadius: 460
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Header

/// The name of the app, the record button, and the glasses.
struct HomeHeader: View {
    let glasses: GlassesStatus
    let canRecord: Bool
    let isRecording: Bool
    let onGlasses: () -> Void
    let onRecord: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(wordmark: true)
            row(wordmark: false)
        }
    }

    private func row(wordmark: Bool) -> some View {
        HStack(spacing: Theme.Space.tight) {
            FoxMark()
                .frame(width: 32, height: 32)
            if wordmark {
                Text("Phoenix Fox")
                    .font(Theme.display(.headline))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: Theme.Space.tight)
            if canRecord {
                Button(action: onRecord) {
                    Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.title3)
                        .foregroundStyle(isRecording ? Theme.seeing : Theme.inkSoft)
                        .frame(minWidth: Theme.tapTarget, minHeight: Theme.tapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(isRecording ? "Stop recording" : "Record what I see")
                .accessibilityHint(isRecording ? "Saves the video to Photos." : "Records video from your glasses. The capture light is on while it records.")
            }
            GlassesChip(status: glasses, action: onGlasses)
        }
    }
}

/// The glasses at a glance. A tap opens their settings.
struct GlassesChip: View {
    let status: GlassesStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.tight) {
                Image(systemName: "eyeglasses")
                    .foregroundStyle(tint)
                Text(status.title)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if status == .cameraOn {
                    Circle()
                        .fill(Theme.seeing)
                        .frame(width: 8, height: 8)
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, Theme.Space.snug)
            .frame(minHeight: Theme.tapTarget)
            .floatingGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status.spoken)
        .accessibilityHint("Opens glasses settings.")
    }

    private var tint: Color {
        switch status {
        case .notConnected, .away: return Theme.inkFaint
        case .ready: return Theme.good
        case .cameraOn: return Theme.seeing
        }
    }
}

// MARK: - What is happening

/// The camera is on. This is the one red thing in the app, and it matches the capture
/// light on the glasses.
struct CameraBanner: View {
    var body: some View {
        Label("Camera on. The capture light on your glasses is lit.", systemImage: "eye.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.onSeeing)
            .padding(.horizontal, Theme.Space.normal)
            .padding(.vertical, Theme.Space.snug)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.seeing, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

/// One line with a symbol: a recording that was saved, for instance.
struct NoteRow: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.hair)
    }
}

/// The document that answers are being drawn from. The button puts it away.
struct DocumentRow: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            Image(systemName: "book.fill")
                .foregroundStyle(Theme.emberInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Reading from")
                    .font(.caption)
                    .foregroundStyle(Theme.inkFaint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.inkFaint)
                    .frame(minWidth: Theme.tapTarget, minHeight: Theme.tapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Stop reading from \(title)")
        }
        .card(padding: Theme.Space.snug)
    }
}

/// The companion's status line and, when live captions are on, what is being said nearby.
struct CaptionCard: View {
    let status: String
    let caption: String
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.hair) {
            if !status.isEmpty {
                Text(status)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(large ? .title3.weight(.medium) : .callout)
                    .foregroundStyle(Theme.ink)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// What the wearer just said and what came back.
struct ExchangeCard: View {
    let heard: String
    let reply: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            if !heard.isEmpty {
                line(who: "You", text: heard, color: Theme.inkSoft)
            }
            if !reply.isEmpty {
                line(who: "Jarvis", text: reply, color: Theme.ink)
            }
        }
        .card()
    }

    private func line(who: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(who)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.emberInk)
            Text(text)
                .font(.body)
                .foregroundStyle(color)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The team, before there is one

/// My assistants is chosen and the relay is not set up.
struct ConnectCard: View {
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            SectionHeading(title: "Your team")
            Text("Connect your assistants and each one shows here with what it is doing.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
            Button("Connect your assistants", action: onConnect)
                .buttonStyle(.ember)
        }
        .card()
    }
}

/// Another AI is answering. Says which, and offers the way to change it.
struct BrainCard: View {
    let name: String
    let onChoose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            SectionHeading(title: "Answering")
            Label(name, systemImage: "brain.head.profile")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("Jarvis answers with this AI. Choose My assistants to talk to your own team.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
            Button("Choose who answers", action: onChoose)
                .buttonStyle(.quiet)
        }
        .card()
    }
}

// MARK: - Trouble

/// Something went wrong. It says what in plain words and can be put away.
struct TroubleBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.goldInk)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(minWidth: Theme.tapTarget, minHeight: Theme.tapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, Theme.Space.normal)
        .padding(.vertical, Theme.Space.hair)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.goldInk.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Home, ready") {
    HomeContent(model: HomeSamples.ready)
}

#Preview("Home, listening") {
    HomeContent(model: HomeSamples.listening)
}

#Preview("Home, seeing") {
    HomeContent(model: HomeSamples.seeing)
}

#Preview("Home, asking Indy") {
    HomeContent(model: HomeSamples.asking)
}

#Preview("Home, replying, light") {
    HomeContent(model: HomeSamples.replying)
        .preferredColorScheme(.light)
}

#Preview("Home, first launch") {
    HomeContent(model: HomeSamples.fresh)
}

#Preview("Home, trouble, largest type") {
    HomeContent(model: HomeSamples.trouble)
        .dynamicTypeSize(.accessibility5)
}
#endif
