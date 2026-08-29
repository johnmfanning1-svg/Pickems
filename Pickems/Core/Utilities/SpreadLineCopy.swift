import Foundation

/// Locked Pickems line vs live ESPN line shown for reference.
enum SpreadLineCopy {
    /// Live ESPN line for parentheses, or `nil` when missing or the same as the locked line.
    static func liveReference(locked: String, live: String?) -> String? {
        guard let live else { return nil }
        let trimmed = live.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if normalized(trimmed) == normalized(locked) { return nil }
        return trimmed
    }

    static func caption(locked: String, live: String?) -> String {
        if let live = liveReference(locked: locked, live: live) {
            return "\(locked) (\(live))"
        }
        return locked
    }

    static func accessibilityLabel(locked: String, live: String?, isLocked: Bool) -> String {
        var parts: [String] = []
        if isLocked {
            parts.append("Locked Pickems spread \(locked)")
        } else {
            parts.append("Spread \(locked)")
        }
        if let live = liveReference(locked: locked, live: live) {
            parts.append("Live spread \(live), for reference")
        }
        return parts.joined(separator: ". ")
    }

    private static func normalized(_ value: String) -> String {
        var collapsed = value.replacingOccurrences(of: " ", with: "").lowercased()
        if collapsed.hasSuffix(".0") {
            collapsed = String(collapsed.dropLast(2))
        }
        return collapsed
    }
}
