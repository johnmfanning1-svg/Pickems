import Foundation

enum DisplayNameRules {
    static let minLength = 3
    static let maxLength = 20

    /// Trim + collapse internal whitespace.
    static func normalize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Case-insensitive uniqueness key stored in `handles/{key}`.
    static func uniquenessKey(for displayName: String) -> String {
        normalize(displayName).lowercased()
    }

    /// Nickname / handle: letters, numbers, spaces, underscore, hyphen, period.
    static func validate(_ raw: String) -> Result<String, ValidationError> {
        let name = normalize(raw)
        guard name.count >= minLength else { return .failure(.tooShort) }
        guard name.count <= maxLength else { return .failure(.tooLong) }

        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: " ._-"))
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return .failure(.invalidCharacters)
        }
        // Block names that are only punctuation/spaces after normalize (already trimmed).
        guard name.contains(where: \.isLetter) || name.contains(where: \.isNumber) else {
            return .failure(.invalidCharacters)
        }
        return .success(name)
    }

    enum ValidationError: LocalizedError, Equatable {
        case tooShort
        case tooLong
        case invalidCharacters
        case taken

        var errorDescription: String? {
            switch self {
            case .tooShort:
                return "Display name must be at least \(DisplayNameRules.minLength) characters."
            case .tooLong:
                return "Display name must be \(DisplayNameRules.maxLength) characters or fewer."
            case .invalidCharacters:
                return "Use letters, numbers, spaces, periods, hyphens, or underscores."
            case .taken:
                return "That display name is already taken. Try another nickname or handle."
            }
        }
    }
}
