import Foundation
import os

/// Basic, deterministic content moderation applied to both user input (before it
/// reaches the model) and model output (before it is shown or saved). Deliberately
/// conservative to avoid false positives on ordinary mindfulness conversation.
enum ChatGuardrail {
    enum Category { case Sexual, Violence }
    struct Violation: Equatable { let category: Category; let matchedTerm: String }

    private static let sexualTerms = [
        "porn", "pornographic", "pornography", "xxx video", "nsfw",
        "nude photo", "nude pic", "naked photo", "naked pic", "sex tape",
        "explicit sex", "erotic story", "erotica", "masturbat", "orgasm",
        "genitals", "penis", "vagina", "blowjob", "handjob", "anal sex",
        "hardcore sex", "sexual fantasy",
    ]

    private static let violentTerms = [
        "kill you", "kill him", "kill her", "kill them", "kill myself",
        "murder", "slaughter", "massacre", "torture", "gore", "behead",
        "stab you", "stab him", "stab her", "shoot you", "shoot him",
        "shoot her", "mutilat", "dismember", "graphic violence",
        "how to make a bomb", "how to build a bomb", "hurt you badly",
        "beat you to death",
    ]

    private static let log = Logger(subsystem: "com.tatvaum.connect", category: "ChatGuardrail")

    static func evaluate(_ text: String) -> Violation? {
        let lower = text.lowercased()
        if let t = sexualTerms.first(where: lower.contains) {
            log.info("blocked sexual content — matched: \(t)")
            return Violation(category: .Sexual, matchedTerm: t)
        }
        if let t = violentTerms.first(where: lower.contains) {
            log.info("blocked violent content — matched: \(t)")
            return Violation(category: .Violence, matchedTerm: t)
        }
        return nil
    }

    static func fallbackMessage(_ v: Violation) -> String {
        switch v.category {
        case .Sexual:
            "I'm not able to engage with sexual content. I'm here to support your wellbeing — is there something on your mind I can help with instead?"
        case .Violence:
            "I'm not able to engage with violent content. If you're having thoughts of harming yourself or someone else, please reach out to a crisis line or someone you trust right away. Is there something else I can help with?"
        }
    }
}
