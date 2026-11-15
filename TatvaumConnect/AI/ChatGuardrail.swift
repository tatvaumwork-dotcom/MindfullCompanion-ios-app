import Foundation
import os

/// Basic, deterministic content checks applied to user input (before it reaches the model)
/// and model output (before it is shown or saved).
///
/// - Sexual and violent content is blocked: a fixed reply is shown instead.
/// - Self-harm is not blocked. It's a sign someone may be at risk, so the chat shows a crisis
///   support card with helplines and the companion still replies with care.
///
/// Terms match whole words only ("gore" doesn't match "gorgeous"); a term ending in `*` matches
/// any word starting with it ("murder*" matches "murderer"). Everyday phrases in `allowed`
/// ("this week has been torture", "murder mystery") are ignored before matching.
enum ChatGuardrail {
    enum Category { case Sexual, Violence, SelfHarm }
    struct Violation: Equatable { let category: Category; let matchedTerm: String }

    private static let sexualTerms = [
        "porn*", "xxx", "nsfw",
        "nude photo*", "nude pic*", "naked photo*", "naked pic*", "sex tape*",
        "explicit sex", "erotic story", "erotic stories", "erotica", "masturbat*", "orgasm*",
        "genitals", "penis", "vagina", "blowjob*", "handjob*", "anal sex",
        "hardcore sex", "sexual fantasy", "sexual fantasies",
    ]

    private static let violentTerms = [
        "kill you", "kill him", "kill her", "kill them",
        "murder*", "slaughter", "slaughtered", "massacre*", "tortur*", "gore", "gory", "behead*",
        "stab you", "stab him", "stab her", "shoot you", "shoot him", "shoot her",
        "mutilat*", "dismember*", "graphic violence",
        "how to make a bomb", "how to build a bomb", "hurt you badly", "beat you to death",
    ]

    /// Signs the person may be thinking of suicide or self-harm (checked on input only).
    private static let selfHarmTerms = [
        "kill myself", "killing myself", "end my life", "ending my life", "take my own life", "taking my own life",
        "suicide", "suicidal", "want to die", "wanna die", "wish i was dead", "wish i were dead", "better off dead",
        "no reason to live", "nothing to live for", "don't want to live", "dont want to live", "not worth living",
        "end it all", "self harm", "self-harm", "hurt myself", "harm myself", "cut myself", "cutting myself",
        "overdose", "unalive myself",
    ]

    /// Ordinary phrases that contain a listed word but aren't harmful.
    private static let allowed = [
        "murder mystery", "murder mysteries", "murder mystery novel", "murder podcast", "murder she wrote",
        "been torture", "is torture", "was torture", "pure torture", "absolute torture", "such torture", "sheer torture",
        "al gore", "chainsaw massacre",
        "killing it", "kill it", "killed it", "dressed to kill", "kill time", "killing time",
    ]

    private static let log = Logger(subsystem: "com.tatvaum.connect", category: "ChatGuardrail")

    /// Checks `text`. Self-harm is only looked for in the person's own messages (`isInput`),
    /// so a caring reply that mentions it isn't replaced.
    static func evaluate(_ text: String, isInput: Bool = true) -> Violation? {
        var words = tokens(text)
        for phrase in allowed.map(tokens) { blank(phrase, in: &words) }
        if let t = sexualTerms.first(where: { matches($0, words) }) {
            log.info("blocked sexual content — matched: \(t)")
            return Violation(category: .Sexual, matchedTerm: t)
        }
        if let t = violentTerms.first(where: { matches($0, words) }) {
            log.info("blocked violent content — matched: \(t)")
            return Violation(category: .Violence, matchedTerm: t)
        }
        if isInput, let t = selfHarmTerms.first(where: { matches($0, words) }) {
            log.info("self-harm signal — matched: \(t)")
            return Violation(category: .SelfHarm, matchedTerm: t)
        }
        return nil
    }

    /// Whether a violation stops the message (true) or only adds support alongside the reply (false).
    static func blocks(_ v: Violation) -> Bool { v.category != .SelfHarm }

    static func fallbackMessage(_ v: Violation) -> String {
        switch v.category {
        case .Sexual:
            "I'm not able to engage with sexual content. I'm here to support your wellbeing — is there something on your mind I can help with instead?"
        case .Violence:
            "I'm not able to engage with violent content. If you're having thoughts of harming yourself or someone else, please reach out to a crisis line or someone you trust right away. Is there something else I can help with?"
        case .SelfHarm:
            CrisisSupport.text()
        }
    }

    // MARK: matching

    /// Lowercased words: letters, digits and apostrophes (curly ones straightened); hyphens split words.
    static func tokens(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map(String.init)
    }

    /// `term` as a run of consecutive words; a trailing `*` on the last word matches any word starting with it.
    private static func matches(_ term: String, _ words: [String]) -> Bool {
        let wildcard = term.hasSuffix("*")
        let parts = tokens(wildcard ? String(term.dropLast()) : term)
        guard !parts.isEmpty, words.count >= parts.count else { return false }
        for start in 0...(words.count - parts.count) {
            var ok = true
            for (k, part) in parts.enumerated() {
                let w = words[start + k]
                let last = k == parts.count - 1
                if !(w == part || (last && wildcard && w.hasPrefix(part))) { ok = false; break }
            }
            if ok { return true }
        }
        return false
    }

    /// Replaces every occurrence of `phrase` in `words` with empty strings so it can't match.
    private static func blank(_ phrase: [String], in words: inout [String]) {
        guard !phrase.isEmpty, words.count >= phrase.count else { return }
        for start in 0...(words.count - phrase.count) where Array(words[start..<(start + phrase.count)]) == phrase {
            for k in start..<(start + phrase.count) { words[k] = "" }
        }
    }
}
