import Foundation

/// User-facing notification categories stored on `users/{uid}` (defaults)
/// and optionally overridden on `groups/{groupId}/members/{uid}`.
/// Missing Firestore fields default to on so existing accounts keep getting alerts.
enum NotificationPrefCategory: String, CaseIterable, Identifiable, Sendable {
    case selectionDeadlines
    case pickemsDeadlines
    case gameFinals
    case tookTheLead
    case weekScored
    case seasonClosed
    case chatMessages
    case commissionerDeadlines

    var id: String { rawValue }

    var firestoreField: String {
        switch self {
        case .selectionDeadlines: return "notifySelectionDeadlines"
        case .pickemsDeadlines: return "notifyPickemsDeadlines"
        case .gameFinals: return "notifyGameFinals"
        case .tookTheLead: return "notifyTookTheLead"
        case .weekScored: return "notifyWeekScored"
        case .seasonClosed: return "notifySeasonClosed"
        case .chatMessages: return "notifyChatMessages"
        case .commissionerDeadlines: return "notifyCommissionerDeadlines"
        }
    }

    var title: String {
        switch self {
        case .selectionDeadlines: return "Selection deadlines"
        case .pickemsDeadlines: return "Pickems deadlines"
        case .gameFinals: return "Game results"
        case .tookTheLead: return "Took the lead"
        case .weekScored: return "Week scored"
        case .seasonClosed: return "Season closed"
        case .chatMessages: return "Chat messages"
        case .commissionerDeadlines: return "Commissioner deadlines"
        }
    }

    var subtitle: String {
        switch self {
        case .selectionDeadlines:
            return "Reminders to finish Selections before the nomination deadline."
        case .pickemsDeadlines:
            return "Pickems are open, lock-in reminders, and when the board locks."
        case .gameFinals:
            return "You covered, tough beat, or push when a slate game goes final."
        case .tookTheLead:
            return "You’re #1 on the live board."
        case .weekScored:
            return "The week is scored and the leaderboard is ready."
        case .seasonClosed:
            return "The season is archived and a champion is crowned."
        case .chatMessages:
            return "New league chat messages."
        case .commissionerDeadlines:
            return "Nudge to set a Selection deadline, and when it passes with an empty slate."
        }
    }

    var systemImage: String {
        switch self {
        case .selectionDeadlines: return "american.football.fill"
        case .pickemsDeadlines: return "checkmark.circle"
        case .gameFinals: return "sportscourt"
        case .tookTheLead: return "crown"
        case .weekScored: return "flag.checkered"
        case .seasonClosed: return "trophy"
        case .chatMessages: return "bubble.left.and.bubble.right"
        case .commissionerDeadlines: return "person.badge.shield.checkmark"
        }
    }

    enum Group: String, CaseIterable, Identifiable, Sendable {
        case deadlines
        case games
        case league
        case commissioner

        var id: String { rawValue }

        var title: String {
            switch self {
            case .deadlines: return "Deadlines"
            case .games: return "Games & standings"
            case .league: return "League"
            case .commissioner: return "Commissioner"
            }
        }
    }

    var group: Group {
        switch self {
        case .selectionDeadlines, .pickemsDeadlines: return .deadlines
        case .gameFinals, .tookTheLead, .weekScored: return .games
        case .seasonClosed, .chatMessages: return .league
        case .commissionerDeadlines: return .commissioner
        }
    }

    /// FCM `type` values this toggle gates. Unknown types stay on.
    var pushTypes: [String] {
        switch self {
        case .selectionDeadlines:
            return ["selection_deadline_reminder"]
        case .pickemsDeadlines:
            return ["pickems_open", "deadline_reminder", "deadline_locked", "deadline_passed"]
        case .gameFinals:
            return ["game_final"]
        case .tookTheLead:
            return ["took_the_lead"]
        case .weekScored:
            return ["week_scored"]
        case .seasonClosed:
            return ["season_closed"]
        case .chatMessages:
            return ["chat_message"]
        case .commissionerDeadlines:
            return ["set_selection_deadline", "selection_deadline_passed"]
        }
    }

    static var memberFacing: [NotificationPrefCategory] {
        allCases.filter { $0.group != .commissioner }
    }

    static func categories(in group: Group) -> [NotificationPrefCategory] {
        allCases.filter { $0.group == group }
    }

    /// Member override if present, else account default, else on.
    /// `chatMuted` on the member doc is an extra chat off-switch (in-thread mute).
    /// Commissioner alerts fall back to the legacy Selection-deadlines pref when unset.
    static func isEnabled(
        _ category: NotificationPrefCategory,
        stored: (NotificationPrefCategory) -> Bool?,
        inherited: ((NotificationPrefCategory) -> Bool)? = nil,
        chatMuted: Bool? = nil
    ) -> Bool {
        if category == .chatMessages, chatMuted == true {
            return false
        }
        if let value = stored(category) {
            return value
        }
        if let inherited {
            return inherited(category)
        }
        if category == .commissionerDeadlines, let selection = stored(.selectionDeadlines) {
            return selection
        }
        return true
    }

    /// Whether a push `type` should be delivered given the user's category switches.
    static func shouldDeliver(type: String, isEnabled: (NotificationPrefCategory) -> Bool) -> Bool {
        guard let category = allCases.first(where: { $0.pushTypes.contains(type) }) else {
            return true
        }
        return isEnabled(category)
    }
}
