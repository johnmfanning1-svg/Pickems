import Foundation

enum InviteCodeRules {
    static let minLength = 4
    static let maxLength = 8

    static func normalize(_ raw: String) -> String {
        raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidFormat(_ raw: String) -> Bool {
        let code = normalize(raw)
        guard (minLength...maxLength).contains(code.count) else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return code.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
