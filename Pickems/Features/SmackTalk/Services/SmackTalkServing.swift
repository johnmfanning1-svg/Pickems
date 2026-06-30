import Foundation

/// Backend contract for week-scoped league smack talk.
/// Swap `LocalSmackTalkService` for a Firestore-backed implementation in production.
protocol SmackTalkServing: AnyObject {
    func messages(for thread: WeekThread) -> [SmackTalkMessage]
    func observeMessages(for thread: WeekThread, onChange: @escaping ([SmackTalkMessage]) -> Void)
    func stopObserving(for thread: WeekThread)
    func sendMessage(text: String, context: SmackTalkContext) async throws
    func postSystemMessage(text: String, thread: WeekThread) async throws
}

enum SmackTalkError: LocalizedError {
    case emptyMessage
    case messageTooLong

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Say something before you send it."
        case .messageTooLong:
            return "Keep it under 280 characters."
        }
    }
}
