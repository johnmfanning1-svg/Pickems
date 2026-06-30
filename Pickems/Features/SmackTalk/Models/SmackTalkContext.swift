import Foundation

/// Current user and league context for sending smack talk.
struct SmackTalkContext: Equatable {
    let userId: String
    let displayName: String
    let thread: WeekThread
}
