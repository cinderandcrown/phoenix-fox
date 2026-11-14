// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI

/// One assistant: who it is and what it is doing.
///
/// A card is one VoiceOver element that says the name, the status, and how long it has
/// been working. Status is never carried by color alone: each has its own symbol and words.
struct TeamCard: View {
    let member: TeamBoard.Member
    let now: Date
    /// Draws nothing that moves. For previews and snapshot tests.
    var still = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            Monogram(text: member.monogram, lit: member.isWorking)

            VStack(alignment: .leading, spacing: Theme.Space.hair) {
                Text(member.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(TeamBoard.line(for: member.status, now: now))
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(3)
                if case .working(_, let since) = member.status {
                    Text("For \(TeamBoard.duration(now.timeIntervalSince(since)))")
                        .font(.caption)
                        .foregroundStyle(Theme.inkFaint)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            glyph
                .font(.body.weight(.semibold))
                .frame(minWidth: 24)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TeamBoard.spoken(for: member, now: now))
        .accessibilityHint("Shows recent work.")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var glyph: some View {
        switch member.status {
        case .ready:
            Image(systemName: "circle").foregroundStyle(Theme.inkFaint)
        case .working:
            if still {
                Image(systemName: "ellipsis.circle.fill").foregroundStyle(Theme.emberInk)
            } else {
                ProgressView().tint(Theme.emberInk)
            }
        case .answered:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
        case .alerted(_, _, let urgent):
            Image(systemName: urgent ? "exclamationmark.circle.fill" : "bell.fill").foregroundStyle(Theme.emberInk)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.goldInk)
        }
    }
}

/// An assistant's initials on a coal. It glows while the assistant is working.
struct Monogram: View {
    let text: String
    let lit: Bool

    @ScaledMetric(relativeTo: .headline) private var side: CGFloat = 44

    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .serif, weight: .bold))
            .foregroundStyle(lit ? Theme.onFire : Theme.emberInk)
            .frame(width: side, height: side)
            .background {
                if lit {
                    Circle().fill(Theme.buttonGradient)
                } else {
                    Circle().fill(Theme.raised)
                }
            }
            .overlay(Circle().strokeBorder(lit ? Theme.gold : Theme.hairline, lineWidth: 1))
            .animation(Theme.Motion.state, value: lit)
            .accessibilityHidden(true)
    }
}

/// "Your team": a heading and a card for each assistant.
struct TeamSection: View {
    let members: [TeamBoard.Member]
    let now: Date
    let wakeWord: String
    var still = false

    @State private var selected: Selection? = nil

    private struct Selection: Identifiable {
        let id: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            SectionHeading(title: "Your team", detail: summary)

            ForEach(members) { member in
                Button {
                    selected = Selection(id: member.id)
                } label: {
                    TeamCard(member: member, now: now, still: still)
                }
                .buttonStyle(.plain)
            }

            Text("To ask everyone at once, say \(TeamBoard.exampleForEveryone(wakeWord: wakeWord))")
                .font(.footnote)
                .foregroundStyle(Theme.inkFaint)
        }
        .animation(Theme.Motion.state, value: members)
        .sheet(item: $selected) { selection in
            if let member = members.first(where: { $0.id == selection.id }) {
                AssistantSheet(member: member, now: now, wakeWord: wakeWord)
            }
        }
    }

    private var summary: String? {
        let working = members.filter(\.isWorking).count
        return working == 0 ? nil : "\(working) working"
    }
}

/// A serif heading for a part of the home screen, with an optional note at the far side.
struct SectionHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.display(.title3))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.tight)
            if let detail {
                Text(detail)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.emberInk)
            }
        }
    }
}

/// What one assistant has been doing, and how to ask it for something.
struct AssistantSheet: View {
    let member: TeamBoard.Member
    let now: Date
    let wakeWord: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Now") {
                    Text(TeamBoard.line(for: member.status, now: now))
                }

                Section {
                    Text(TeamBoard.example(for: member, wakeWord: wakeWord))
                } header: {
                    Text("Try saying")
                } footer: {
                    Text(member.isDefault
                         ? "\(member.name) answers when you do not name anyone."
                         : "Say the name and \(member.name) gets the request.")
                }

                Section {
                    if member.events.isEmpty {
                        Text("Nothing yet since Phoenix Fox was opened.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(member.events) { event in
                        VStack(alignment: .leading, spacing: Theme.Space.hair) {
                            Text("\(event.kind.label), \(TeamBoard.ago(event.at, now: now))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(event.text)
                                .font(.body)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Recent")
                } footer: {
                    Text("This list is kept while the app is open. Whole conversations are in History.")
                }
            }
            .navigationTitle(member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#if DEBUG
#Preview("Team") {
    ScrollView {
        TeamSection(members: HomeSamples.team, now: HomeSamples.now, wakeWord: "Jarvis")
            .padding()
    }
    .background(Theme.canvas)
}

#Preview("Assistant") {
    AssistantSheet(member: HomeSamples.team[1], now: HomeSamples.now, wakeWord: "Jarvis")
}
#endif
