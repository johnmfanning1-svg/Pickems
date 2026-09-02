import Foundation

/// User-facing notification categories stored on `users/{uid}`.
/// Missing Firestore fields default to on so existing accounts keep getting alerts.
enum NotificationPrefCategory: String, CaseIterable, Identifiable, Sendable {
    case selectionDeadlines
    case pickemsDeadlines
    case gameFinals
    case tookTheLead
    case weekScored
    case seasonClosed
    case chatMessages

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
        }
    }

    var subtitle: String {
        switch self {
        case .selectionDeadlines:
            return "Reminders to finish Selections, plus commissioner nudges to set a deadline."
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
            return "New league chat messages. You can still mute a league in chat."
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
        }
    }

    enum Group: String, CaseIterable, Identifiable, Sendable {
        case deadlines
        case games
        case league

        var id: String { rawValue }

        var title: String {
            switch self {
            case .deadlines: return "Deadlines"
            case .games: return "Games & standings"
            case .league: return "League"
            }
        }
    }

    var group: Group {
        switch self {
        case .selectionDeadlines, .pickemsDeadlines: return .deadlines
        case .gameFinals, .tookTheLead, .weekScored: return .games
        case .seasonClosed, .chatMessages: return .league
        }
    }

    /// FCM `type` values this toggle gates. Unknown types stay on.
    var pushTypes: [String] {
        switch self {
        case .selectionDeadlines:
            return ["set_selection_deadline", "selection_deadline_reminder", "selection_deadline_passed"]
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
        }
    }

    static func categories(in group: Group) -> [NotificationPrefCategory] {
        allCases.filter { $0.group == group }
    }

    /// Whether a push `type` should be delivered given the user's category switches.
    static func shouldDeliver(type: String, isEnabled: (NotificationPrefCategory) -> Bool) -> Bool {
        guard let category = allCases.first(where: { $0.pushTypes.contains(type) }) else {
            return true
        }
        return isEnabled(category)
    }
}
