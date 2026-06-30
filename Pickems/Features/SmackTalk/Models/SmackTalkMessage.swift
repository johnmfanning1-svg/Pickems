import Foundation

enum SmackTalkMessageKind: String, Codable, Equatable {
    case user
    case system
}

struct SmackTalkMessage: Identifiable, Codable, Equatable {
    let id: String
    let threadId: String
    let userId: String
    let displayName: String
    let text: String
    let createdAt: Date
    let kind: SmackTalkMessageKind

    var isFromCurrentUser: Bool {
        kind == .user
    }
}
