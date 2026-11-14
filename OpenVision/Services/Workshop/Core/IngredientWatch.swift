// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Checks the words of an ingredient label against the wearer's own list of allergens.
//
// The label is read by the phone's text recognition and matched here against fixed word
// lists. No model describes the label and nothing leaves the phone. The answer quotes the
// words that were read, so the wearer hears the evidence and not a judgment, and it never
// says a product is safe: a missed word in small print is always possible.
//
// The word lists cover the allergens that must be declared in the United States and the
// European Union, by the names they commonly go under in English.

import Foundation

struct Allergen: Equatable, Identifiable, Sendable {
    var id: String
    /// How it is said: "milk", "tree nuts".
    var name: String
    /// Words and phrases that mean this allergen is an ingredient.
    var terms: [String]
    /// Phrases that contain one of the terms and mean something else.
    var innocent: [String] = []

    static let catalog: [Allergen] = [
        Allergen(
            id: "milk", name: "milk",
            terms: ["milk", "whey", "casein", "caseinate", "lactose", "butter", "buttermilk", "butterfat", "cream", "cheese",
                    "yogurt", "yoghurt", "ghee", "curd", "lactalbumin", "lactoglobulin", "milkfat", "dairy"],
            innocent: ["cocoa butter", "shea butter", "peanut butter", "almond butter", "cashew butter", "nut butter",
                       "sunflower butter", "coconut milk", "almond milk", "oat milk", "soy milk", "soya milk", "rice milk",
                       "coconut cream", "cream of tartar", "non dairy"]
        ),
        Allergen(
            id: "egg", name: "egg",
            terms: ["egg", "albumen", "albumin", "ovalbumin", "ovomucoid", "lysozyme", "mayonnaise", "meringue"]
        ),
        Allergen(
            id: "fish", name: "fish",
            terms: ["fish", "anchovy", "anchovies", "cod", "salmon", "tuna", "tilapia", "pollock", "haddock", "trout",
                    "sardine", "mackerel", "herring", "bass"]
        ),
        Allergen(
            id: "shellfish", name: "shellfish",
            terms: ["shellfish", "crustacean", "shrimp", "prawn", "crab", "lobster", "crayfish", "crawfish", "krill", "langoustine"]
        ),
        Allergen(
            id: "molluscs", name: "molluscs",
            terms: ["mollusc", "mollusk", "clam", "mussel", "oyster", "scallop", "squid", "calamari", "octopus", "snail", "abalone"]
        ),
        Allergen(
            id: "tree-nuts", name: "tree nuts",
            terms: ["tree nut", "nut", "almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut", "filbert", "macadamia",
                    "brazil nut", "pine nut", "chestnut", "praline", "marzipan", "gianduja"],
            innocent: ["water chestnut"]
        ),
        Allergen(
            id: "peanuts", name: "peanuts",
            terms: ["peanut", "groundnut", "arachis"]
        ),
        Allergen(
            id: "wheat", name: "wheat",
            terms: ["wheat", "semolina", "durum", "spelt", "farro", "kamut", "einkorn", "couscous", "bulgur", "seitan"]
        ),
        Allergen(
            id: "gluten", name: "gluten",
            terms: ["gluten", "wheat", "barley", "rye", "malt", "oat", "triticale", "spelt", "semolina", "durum", "farro",
                    "kamut", "einkorn", "couscous", "bulgur", "seitan"]
        ),
        Allergen(
            id: "soy", name: "soy",
            terms: ["soy", "soya", "soybean", "soja", "edamame", "tofu", "tempeh", "miso"]
        ),
        Allergen(
            id: "sesame", name: "sesame",
            terms: ["sesame", "tahini", "benne", "gingelly"]
        ),
        Allergen(id: "celery", name: "celery", terms: ["celery", "celeriac"]),
        Allergen(id: "mustard", name: "mustard", terms: ["mustard"]),
        Allergen(id: "lupin", name: "lupin", terms: ["lupin", "lupine"]),
        Allergen(
            id: "sulfites", name: "sulfites",
            terms: ["sulfite", "sulphite", "sulfur dioxide", "sulphur dioxide", "metabisulfite", "metabisulphite",
                    "bisulfite", "bisulphite", "e220", "e221", "e222", "e223", "e224", "e225", "e226", "e227", "e228"]
        ),
    ]

    /// The catalog entry a spoken name means: "nuts", "dairy", "shellfish".
    static func named(_ spoken: String) -> Allergen? {
        let words = WorkshopText.words(spoken).filter { !["my", "the", "allergy", "allergies", "allergen"].contains($0) }
        let said = words.joined(separator: " ")
        guard !said.isEmpty else { return nil }
        let aliases: [String: String] = [
            "dairy": "milk", "lactose": "milk", "eggs": "egg", "nuts": "tree-nuts", "nut": "tree-nuts",
            "tree nut": "tree-nuts", "peanut": "peanuts", "soya": "soy", "sulphites": "sulfites",
            "sulfite": "sulfites", "mollusks": "molluscs", "crustaceans": "shellfish", "seafood": "shellfish",
        ]
        let id = aliases[said] ?? said.replacingOccurrences(of: " ", with: "-")
        return catalog.first { $0.id == id || $0.name == said }
    }
}

enum IngredientWatch {
    enum Certainty: Equatable, Sendable {
        /// In the ingredient list or a "contains" statement.
        case listed
        /// In a "may contain" or shared-equipment statement.
        case mayContain
    }

    struct Finding: Equatable, Sendable {
        /// What the wearer watches for: an allergen's name, or their own word.
        var name: String
        var certainty: Certainty
        /// The words read from the label, with the two before them.
        var evidence: String
    }

    struct Report: Equatable, Sendable {
        var findings: [Finding]
        /// "Free from" claims on the pack that name something on the list.
        var claims: [String]
        /// Whether the text read like an ingredient label at all.
        var sawIngredients: Bool
        var wordCount: Int

        var isEmpty: Bool { findings.isEmpty }
    }

    /// The fewest words that count as having read a label.
    static let minimumWords = 6

    private static let precaution = [
        "may contain", "may also contain", "traces of", "trace of", "in a facility", "in a factory", "on equipment",
        "shared equipment", "same facility", "same equipment", "same line", "same lines", "in an environment",
        "cannot guarantee", "not suitable for",
    ]

    /// Checks the text of a label.
    ///
    /// - Parameters:
    ///   - text: The label as read, lines joined by line breaks.
    ///   - watched: Ids from `Allergen.catalog`.
    ///   - custom: The wearer's own words, matched as written.
    static func scan(_ text: String, watched: [String], custom: [String] = []) -> Report {
        var targets: [(name: String, terms: [String], innocent: [String])] = Allergen.catalog
            .filter { watched.contains($0.id) }
            .map { ($0.name, $0.terms, $0.innocent) }
        for word in custom {
            let term = WorkshopText.words(word).joined(separator: " ")
            if !term.isEmpty { targets.append((term, [term], [])) }
        }

        // A statement ends at a full stop. Line breaks do not end one: a label wraps
        // "may contain" onto the next line as often as not.
        let statements = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { ".;!".contains($0) })
            .map { tokens(String($0)) }
            .filter { !$0.isEmpty }
        let allWords = statements.flatMap { $0 }.filter { $0 != separator }
        let whole = " " + allWords.joined(separator: " ") + " "

        var findings: [Finding] = []
        var claims: [String] = []
        for target in targets {
            var best: Finding?
            var claimed = false
            for words in statements {
                var cleared = words
                for phrase in target.innocent {
                    cleared = blank(phrase, in: cleared)
                }
                let cautions = precaution.flatMap { indices(of: $0, in: words) }
                for term in target.terms {
                    for index in indices(of: term, in: cleared) {
                        if isFreeFrom(words, at: index, length: term.split(separator: " ").count) {
                            claimed = true
                            continue
                        }
                        let certainty: Certainty = isPrecaution(words, at: index, cautions: cautions) ? .mayContain : .listed
                        // "Listed" is kept over "may contain" when a label says both.
                        if best == nil || (best?.certainty == .mayContain && certainty == .listed) {
                            best = Finding(name: target.name, certainty: certainty, evidence: evidence(words, at: index, term: term))
                        }
                    }
                }
            }
            if let best {
                findings.append(best)
            } else if claimed {
                claims.append(target.name)
            }
        }

        let markers = [" ingredients ", " ingredient ", " contains ", " contain ", " allergens ", " allergen ", " allergy "]
        return Report(
            findings: ordered(findings),
            claims: claims,
            sawIngredients: markers.contains { whole.contains($0) },
            wordCount: allWords.count
        )
    }

    /// Two readings of the same label, joined. For an allergen the cautious answer is
    /// everything either reading found.
    static func merged(_ first: Report, _ second: Report) -> Report {
        var findings = first.findings
        for finding in second.findings {
            if let index = findings.firstIndex(where: { $0.name == finding.name }) {
                if findings[index].certainty == .mayContain, finding.certainty == .listed { findings[index] = finding }
            } else {
                findings.append(finding)
            }
        }
        let found = Set(findings.map(\.name))
        var claims = first.claims
        for claim in second.claims where !claims.contains(claim) { claims.append(claim) }
        return Report(
            findings: ordered(findings),
            claims: claims.filter { !found.contains($0) },
            sawIngredients: first.sawIngredients || second.sawIngredients,
            wordCount: max(first.wordCount, second.wordCount)
        )
    }

    /// What is said. `watching` is the wearer's list by name, said back so they know what
    /// was and was not looked for.
    static func spoken(_ report: Report, watching: [String]) -> String {
        guard !watching.isEmpty else {
            return "Your ingredient list is empty. Say, for example, \"add peanuts to my allergies\"."
        }
        if report.findings.isEmpty, report.wordCount < minimumWords || !report.sawIngredients {
            return "I could not find an ingredient list. Hold the label closer, in good light, and ask again."
        }
        var parts: [String] = []
        if report.findings.isEmpty {
            parts.append("I read \(report.wordCount) words and found none of the words I look for on your list: \(WorkshopText.list(watching)).")
            for claim in report.claims {
                parts.append("The pack says it is free from \(claim).")
            }
            parts.append("I can misread small print, so check the label before you rely on this.")
            return parts.joined(separator: " ")
        }
        parts.append("Warning.")
        for finding in report.findings {
            switch finding.certainty {
            case .listed:
                parts.append("This lists \(finding.name). I read: \(finding.evidence).")
            case .mayContain:
                parts.append("It may contain \(finding.name). I read: \(finding.evidence).")
            }
        }
        parts.append("I may have missed other words. Check the label yourself.")
        return parts.joined(separator: " ")
    }

    /// What is listed comes before what may be there, each in the order of the wearer's list.
    private static func ordered(_ findings: [Finding]) -> [Finding] {
        findings.filter { $0.certainty == .listed } + findings.filter { $0.certainty == .mayContain }
    }

    // MARK: - Matching words

    /// Where `term` starts in `words`, as whole words, with a plural allowed on its last word.
    private static func indices(of term: String, in words: [String]) -> [Int] {
        let parts = term.split(separator: " ").map(String.init)
        guard !parts.isEmpty, words.count >= parts.count else { return [] }
        var found: [Int] = []
        for start in 0...(words.count - parts.count) {
            var matches = true
            for (offset, part) in parts.enumerated() {
                let word = words[start + offset]
                let last = offset == parts.count - 1
                if word == part || (last && (word == part + "s" || word == part + "es")) { continue }
                matches = false
                break
            }
            if matches { found.append(start) }
        }
        return found
    }

    /// The mark that stands for a comma, a colon, or a bracket between words.
    ///
    /// Without it "rice, milk" reads as "rice milk", which is a drink with no milk in it.
    /// No phrase matches across one.
    private static let separator = ","

    private static func tokens(_ statement: String) -> [String] {
        var result: [String] = []
        var word = ""
        func close() {
            if !word.isEmpty { result.append(word) }
            word = ""
        }
        for character in statement.lowercased().replacingOccurrences(of: "’", with: "'") {
            if character.isLetter || character.isNumber || character == "'" {
                word.append(character)
            } else {
                close()
                if ",:()[]{}/|•·*".contains(character), result.last != separator, !result.isEmpty {
                    result.append(separator)
                }
            }
        }
        close()
        if result.last == separator { result.removeLast() }
        return result
    }

    /// Whether the word at `index` comes under a "may contain" statement: after one, with
    /// no "ingredients" or "contains" in between to start a new list.
    private static func isPrecaution(_ words: [String], at index: Int, cautions: [Int]) -> Bool {
        guard let caution = cautions.filter({ $0 < index }).max() else { return false }
        return !words[caution..<index].contains { $0 == "ingredients" || $0 == "contains" }
    }

    /// Replaces a phrase with blanks, so the words in it are not matched.
    private static func blank(_ phrase: String, in words: [String]) -> [String] {
        let length = phrase.split(separator: " ").count
        var cleared = words
        for start in indices(of: phrase, in: words) {
            for index in start..<(start + length) { cleared[index] = "" }
        }
        return cleared
    }

    /// "gluten free", "free from milk", "free of nuts, eggs and soy".
    ///
    /// A list after "free from" runs to the end of the statement, unless a word in between
    /// starts a new thought: "free from colours, contains milk" still lists milk.
    private static func isFreeFrom(_ words: [String], at index: Int, length: Int) -> Bool {
        let after = index + length
        if after < words.count, words[after] == "free" {
            // "milk, free range eggs" lists milk. So does "milk, free from gluten".
            let next = after + 1 < words.count ? words[after + 1] : ""
            if !["range", "run", "flowing", "from", "of"].contains(next) { return true }
        }
        guard index >= 2 else { return false }
        for start in stride(from: index - 2, through: 0, by: -1) {
            if ["contains", "contain", "ingredients", "with", "made", "may", "has", "includes"].contains(words[start + 1]) {
                // A new thought has started.
                return false
            }
            if words[start] == "free", ["from", "of"].contains(words[start + 1]) { return true }
        }
        return false
    }

    /// The words read around a match: up to two before and two after, without crossing a
    /// comma, so "skimmed milk powder" is quoted whole and its neighbours are not.
    private static func evidence(_ words: [String], at index: Int, term: String) -> String {
        let length = term.split(separator: " ").count
        var start = index
        while start > 0, index - start < 2, words[start - 1] != separator { start -= 1 }
        var end = index + length
        while end < words.count, end - (index + length) < 2, words[end] != separator, !["and", "or"].contains(words[end]) { end += 1 }
        return words[start..<end].joined(separator: " ")
    }
}
