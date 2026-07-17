import Foundation

/// Unique public username (handle) shown in leagues.
enum DisplayNameRules {
    static let minLength = 3
    static let maxLength = 20

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Case-insensitive uniqueness key stored in `handles/{key}`.
    static func uniquenessKey(for username: String) -> String {
        normalize(username).lowercased()
    }

    /// Username: letters, numbers, underscore only (no spaces).
    static func validate(_ raw: String) -> Result<String, ValidationError> {
        let name = normalize(raw)
        guard name.count >= minLength else { return .failure(.tooShort) }
        guard name.count <= maxLength else { return .failure(.tooLong) }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return .failure(.invalidCharacters)
        }
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
                return "Username must be at least \(DisplayNameRules.minLength) characters."
            case .tooLong:
                return "Username must be \(DisplayNameRules.maxLength) characters or fewer."
            case .invalidCharacters:
                return "Usernames can only use letters, numbers, and underscores."
            case .taken:
                return "That username is taken. Try another."
            }
        }
    }
}

enum PersonNameRules {
    static let minLength = 1
    static let maxLength = 40

    static func normalize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    static func validate(_ raw: String, field: String) -> Result<String, ValidationError> {
        let name = normalize(raw)
        guard name.count >= minLength else {
            return .failure(.required(field))
        }
        guard name.count <= maxLength else {
            return .failure(.tooLong(field))
        }
        let allowed = CharacterSet.letters
            .union(.init(charactersIn: " -'"))
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return .failure(.invalid(field))
        }
        return .success(name)
    }

    enum ValidationError: LocalizedError, Equatable {
        case required(String)
        case tooLong(String)
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .required(let field):
                return "Enter your \(field)."
            case .tooLong(let field):
                return "\(field.capitalized) must be \(PersonNameRules.maxLength) characters or fewer."
            case .invalid(let field):
                return "\(field.capitalized) can only use letters, spaces, hyphens, or apostrophes."
            }
        }
    }
}
