import Foundation

/// Locked Pickems line vs the market line shown for reference only.
enum SpreadLineCopy {
    /// Market line when it differs from the locked line; `nil` when missing or unchanged.
    static func liveReference(locked: String, live: String?) -> String? {
        guard let live else { return nil }
        let trimmed = live.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if normalized(trimmed) == normalized(locked) { return nil }
        return trimmed
    }

    /// Locked line only. Parenthetical "X (Y)" format is retired.
    static func caption(locked: String, live: String? = nil) -> String {
        _ = live
        return locked
    }

    /// Signed value for the second line, e.g. `-7.0` or `PK` for an even / pick'em line.
    static func lineValue(from label: String) -> String? {
        guard let magnitude = signedMagnitude(in: label) else { return nil }
        if magnitude == 0 { return "PK" }
        let formatted = abs(magnitude).formatted(.number.precision(.fractionLength(1)))
        return magnitude < 0 ? "-\(formatted)" : "+\(formatted)"
    }

    /// `Current line: -7.0` / `Closing line: -7.0`, or `nil` when omitted.
    static func referenceCaption(locked: String, live: String?, isFinal: Bool) -> String? {
        guard let live = liveReference(locked: locked, live: live),
              let value = lineValue(from: live) else {
            return nil
        }
        let prefix = isFinal ? "Closing line" : "Current line"
        return "\(prefix): \(value)"
    }

    /// Popover copy when the market line has moved away from the locked pick line.
    static func infoMessage(locked: String, live: String, isFinal: Bool) -> String? {
        guard let live = liveReference(locked: locked, live: live),
              let movedValue = lineValue(from: live) else {
            return nil
        }
        let graded = gradedPhrase(locked)
        let movement: String
        if isFinal {
            movement = "The line closed at \(movedValue)."
        } else {
            movement = "Vegas has since moved it to \(movedValue)."
        }
        return "Your pick is graded at \(graded), the line when picks locked. \(movement) That's for reference only and doesn't change your result."
    }

    /// VoiceOver: e.g. `Locked line LSU minus 7.5. Current line minus 7.0.`
    static func accessibilityLabel(
        locked: String,
        live: String?,
        isLocked: Bool,
        isFinal: Bool = false
    ) -> String {
        var parts: [String] = []
        if isLocked {
            parts.append("Locked line \(spokenLabel(locked))")
        } else {
            parts.append("Spread \(spokenLabel(locked))")
        }
        if let live = liveReference(locked: locked, live: live),
           let value = lineValue(from: live) {
            let prefix = isFinal ? "Closing line" : "Current line"
            parts.append("\(prefix) \(spokenValue(value))")
        }
        return parts.joined(separator: ". ") + "."
    }

    // MARK: - Parsing

    private static func gradedPhrase(_ locked: String) -> String {
        if let magnitude = signedMagnitude(in: locked), magnitude == 0 {
            let team = teamAbbreviation(in: locked)
            if let team, !team.isEmpty {
                return "\(team) even (pick'em)"
            }
            return "even (pick'em)"
        }
        return locked
    }

    private static func spokenLabel(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let magnitude = signedMagnitude(in: trimmed) else { return trimmed }
        if magnitude == 0 {
            if let team = teamAbbreviation(in: trimmed), !team.isEmpty {
                return "\(team) pick'em"
            }
            return "pick'em"
        }
        let number = abs(magnitude).formatted(.number.precision(.fractionLength(1)))
        let spokenNumber = magnitude < 0 ? "minus \(number)" : "plus \(number)"
        if let team = teamAbbreviation(in: trimmed), !team.isEmpty {
            return "\(team) \(spokenNumber)"
        }
        return spokenNumber
    }

    private static func spokenValue(_ value: String) -> String {
        if value == "PK" { return "pick'em" }
        if value.hasPrefix("-") {
            return "minus \(String(value.dropFirst()))"
        }
        if value.hasPrefix("+") {
            return "plus \(String(value.dropFirst()))"
        }
        return value
    }

    private static func teamAbbreviation(in label: String) -> String? {
        let parts = label.split(whereSeparator: { $0.isWhitespace })
        guard let first = parts.first else { return nil }
        let token = String(first)
        // Skip a leading signed number with no team.
        if signedMagnitude(in: token) != nil, parts.count == 1 { return nil }
        if token.hasPrefix("+") || token.hasPrefix("-"), Double(token) != nil { return nil }
        return token
    }

    private static func signedMagnitude(in label: String) -> Double? {
        let pattern = /([+-]?\d+\.?\d*)\s*$/
        guard let match = label.firstMatch(of: pattern) else { return nil }
        return Double(match.1)
    }

    private static func normalized(_ value: String) -> String {
        var collapsed = value.replacingOccurrences(of: " ", with: "").lowercased()
        if collapsed.hasSuffix(".0") {
            collapsed = String(collapsed.dropLast(2))
        }
        return collapsed
    }
}
