// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// How Phoenix Fox spends API credits without lowering quality.
//
// Rules, kept here so they can be tested without a network:
// - Camera frames leave the phone only when a request needs vision, shrunk to what the
//   model needs.
// - Simple intents stay on-device or on a cheap/fast model.
// - A request that needs the top model never drops to a weaker one.
// - Conversation context is trimmed before it is sent.
// - Each provider keeps a monthly usage meter, with an optional soft cap that warns.

import Foundation

// MARK: - What a turn needs

/// How much brain a turn needs. Tunable in the model catalog: the mapping of role → model
/// id can change, but a turn that needs `.top` or `.vision` never gets a cheaper role.
enum ModelRole: String, Codable, CaseIterable, Sendable {
    /// Short talk, timers, device controls, greetings.
    case instant
    /// Real reasoning: planning, multi-step answers, named-assistant tasks.
    case top
    /// A look or photo. Always a vision-capable model.
    case vision

    var title: String {
        switch self {
        case .instant: return "Fast"
        case .top: return "Top"
        case .vision: return "Vision"
        }
    }
}

/// Why a turn was given a role. Kept for the log and for tests.
enum TurnNeed: String, Equatable, Sendable {
    case local
    case instant
    case reason
    case vision
}

enum TurnClassifier {
    /// Phrases that need a look. A turn that matches never goes to a text-only model.
    private static let visionPhrases = [
        "look at this", "look at that", "take a look", "take a photo", "take a picture",
        "what am i looking at", "what is this", "what's this", "whats this",
        "what do you see", "what does this say", "translate this", "read this",
        "describe what you see", "who's that", "who is that",
    ]

    /// Phrases that need real reasoning even when fast mode is on.
    private static let reasonPhrases = [
        "plan ", "explain ", "why ", "compare ", "analyze ", "analyse ",
        "write a ", "draft ", "summarize ", "summarise ", "strategy",
        "help me think", "walk me through",
    ]

    /// Phrases that never leave the phone: time, timers, device controls, short replies.
    private static let localPhrases = [
        "what time", "what's the time", "whats the time", "what day", "what's the date",
        "set a timer", "set timer", "cancel timer", "stop timer", "how much time",
        "set an alarm", "volume up", "volume down", "brightness",
        "pause music", "play music", "skip song", "next song",
        "thank you", "thanks", "good night", "good morning", "hello", "hi phoenix", "hey phoenix",
    ]

    static func need(for text: String) -> TurnNeed {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if visionPhrases.contains(where: { lower.contains($0) }) { return .vision }
        if localPhrases.contains(where: { lower.contains($0) }) { return .local }
        if reasonPhrases.contains(where: { lower.contains($0) }) { return .reason }
        if lower.count > 180 { return .reason }
        return .instant
    }

    /// The model role for a need. Local stays out of the catalog.
    static func role(for need: TurnNeed) -> ModelRole? {
        switch need {
        case .local: return nil
        case .instant: return .instant
        case .reason: return .top
        case .vision: return .vision
        }
    }
}

// MARK: - Model catalog (tunable)

/// Default model ids per provider and role. Settings can override each one.
struct ModelCatalog: Equatable, Sendable {
    struct ProviderModels: Equatable, Codable, Sendable {
        var instant: String
        var top: String
        var vision: String
    }

    var grok = ProviderModels(
        instant: "grok-4-fast-non-reasoning",
        top: "grok-4",
        vision: "grok-4"
    )
    var claude = ProviderModels(
        instant: "claude-haiku-4-5",
        top: "claude-sonnet-4-5",
        vision: "claude-sonnet-4-5"
    )
    var openAI = ProviderModels(
        instant: "gpt-4o-mini",
        top: "gpt-4o",
        vision: "gpt-4o"
    )

    /// The model id for a provider and role. Never maps `.top` or `.vision` onto the
    /// instant id: a request that needs the top model keeps it.
    func model(for brain: AIBackendType, role: ModelRole) -> String? {
        let row: ProviderModels?
        switch brain {
        case .grok: row = grok
        case .claude: row = claude
        case .openAI: row = openAI
        default: return nil
        }
        guard let row else { return nil }
        switch role {
        case .instant: return row.instant
        case .top: return row.top
        case .vision: return row.vision
        }
    }
}

// MARK: - Context trim

enum ContextBudget {
    /// How many prior messages to keep (user + assistant pairs × 2).
    static let defaultMessageCap = 8
    /// Characters per message before the middle is cut.
    static let defaultCharsPerMessage = 1_200

    static func trim(
        _ turns: [(role: String, content: String)],
        maxMessages: Int = defaultMessageCap,
        maxChars: Int = defaultCharsPerMessage
    ) -> [(role: String, content: String)] {
        let kept = Array(turns.suffix(max(0, maxMessages)))
        return kept.map { turn in
            (turn.role, shorten(turn.content, to: maxChars))
        }
    }

    static func shorten(_ text: String, to limit: Int) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit, limit > 40 else { return clean }
        let head = limit / 2
        let tail = limit - head - 3
        let start = clean.prefix(head)
        let end = clean.suffix(tail)
        return "\(start)...\(end)"
    }
}

// MARK: - Usage meter

/// One provider's usage this calendar month.
struct ProviderUsageMonth: Equatable, Codable, Sendable {
    var yearMonth: String
    var requests: Int
    var inputTokens: Int
    var outputTokens: Int
    /// Tenths of a US cent, so $0.012 is 12. Avoids floating point in stored settings.
    var estimatedTenthsOfCent: Int

    static func current(now: Date = Date(), calendar: Calendar = .current) -> ProviderUsageMonth {
        let parts = calendar.dateComponents([.year, .month], from: now)
        let stamp = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
        return ProviderUsageMonth(yearMonth: stamp, requests: 0, inputTokens: 0, outputTokens: 0, estimatedTenthsOfCent: 0)
    }

    var estimatedDollars: Double { Double(estimatedTenthsOfCent) / 1_000.0 }

    mutating func add(inputTokens: Int, outputTokens: Int, tenthsOfCent: Int) {
        requests += 1
        self.inputTokens += max(0, inputTokens)
        self.outputTokens += max(0, outputTokens)
        estimatedTenthsOfCent += max(0, tenthsOfCent)
    }
}

/// Per-provider meters and the optional soft cap.
struct ProviderUsageLedger: Equatable, Codable, Sendable {
    var grok = ProviderUsageMonth.current()
    var claude = ProviderUsageMonth.current()
    var openAI = ProviderUsageMonth.current()
    var gemini = ProviderUsageMonth.current()
    /// Soft cap in whole US dollars for the month, across every paid provider. Zero means off.
    var monthlySoftCapDollars: Int = 0
    var warnedThisMonth = false

    mutating func roll(to now: Date = Date(), calendar: Calendar = .current) {
        let stamp = ProviderUsageMonth.current(now: now, calendar: calendar).yearMonth
        if grok.yearMonth != stamp { grok = .current(now: now, calendar: calendar); warnedThisMonth = false }
        if claude.yearMonth != stamp { claude = .current(now: now, calendar: calendar) }
        if openAI.yearMonth != stamp { openAI = .current(now: now, calendar: calendar) }
        if gemini.yearMonth != stamp { gemini = .current(now: now, calendar: calendar) }
    }

    mutating func record(_ brain: AIBackendType, inputTokens: Int, outputTokens: Int, tenthsOfCent: Int, now: Date = Date()) {
        roll(to: now)
        switch brain {
        case .grok: grok.add(inputTokens: inputTokens, outputTokens: outputTokens, tenthsOfCent: tenthsOfCent)
        case .claude: claude.add(inputTokens: inputTokens, outputTokens: outputTokens, tenthsOfCent: tenthsOfCent)
        case .openAI: openAI.add(inputTokens: inputTokens, outputTokens: outputTokens, tenthsOfCent: tenthsOfCent)
        case .geminiLive: gemini.add(inputTokens: inputTokens, outputTokens: outputTokens, tenthsOfCent: tenthsOfCent)
        default: break
        }
    }

    var totalDollars: Double {
        grok.estimatedDollars + claude.estimatedDollars + openAI.estimatedDollars + gemini.estimatedDollars
    }

    /// Soft cap reached: the caller should warn, not hard-block. Quality is not compromised
    /// by refusing a top-model request.
    var softCapReached: Bool {
        monthlySoftCapDollars > 0 && totalDollars >= Double(monthlySoftCapDollars)
    }

    func month(for brain: AIBackendType) -> ProviderUsageMonth? {
        switch brain {
        case .grok: return grok
        case .claude: return claude
        case .openAI: return openAI
        case .geminiLive: return gemini
        default: return nil
        }
    }
}

/// Rough cost in tenths of a US cent. Tunable; used only for the meter, not billing.
enum ProviderPrice {
    static func tenthsOfCent(brain: AIBackendType, role: ModelRole, inputTokens: Int, outputTokens: Int) -> Int {
        // Approximate dollars per million tokens → tenths of a cent per token.
        let (inRate, outRate): (Double, Double) = {
            switch (brain, role) {
            case (.grok, .instant): return (0.20, 0.50)
            case (.grok, _): return (3.00, 15.00)
            case (.claude, .instant): return (1.00, 5.00)
            case (.claude, _): return (3.00, 15.00)
            case (.openAI, .instant): return (0.15, 0.60)
            case (.openAI, _): return (2.50, 10.00)
            case (.geminiLive, _): return (0.50, 2.00)
            default: return (1.00, 3.00)
            }
        }()
        let dollars = (Double(inputTokens) * inRate + Double(outputTokens) * outRate) / 1_000_000.0
        return max(1, Int((dollars * 1_000.0).rounded()))
    }

    /// When a provider returns no usage, estimate from character counts.
    static func estimateTokens(chars: Int) -> Int {
        max(1, chars / 4)
    }
}

// MARK: - Frame policy

/// When a frame may leave the phone for a model.
enum VisionFramePolicy {
    /// Continuous streaming to a model is only for an explicit live-video session.
    static func mayStreamContinuously(liveVideoSession: Bool) -> Bool {
        liveVideoSession
    }

    /// A one-shot look always goes through ImageBudget before upload.
    static let lookMaxEdge: Double = 768
    static let lookQuality: Double = 0.45
    /// Live video frames are smaller: many leave per second.
    static let liveMaxEdge: Double = 512
    static let liveQuality: Double = 0.4
}
