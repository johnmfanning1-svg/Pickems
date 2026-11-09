import Foundation

/// Pure rules for pick-sheet celebrations and the Cover Moment sheet.
/// Views render the result. They do not decide who gets a sheet, a haptic, or a week-win card.
enum CelebrationPolicy {
    enum InlineResult: Equatable {
        case win(title: String)
        case miss
        case push
    }

    enum Feedback: Equatable {
        case success
        case none
    }

    struct ObservedGame: Equatable {
        var id: String
        var isFinal: Bool
        /// `true` covered, `false` missed, `nil` when the pick did not settle (no pick, or a push).
        var isCorrect: Bool?
        var isPush: Bool
    }

    struct Observation: Equatable {
        var seen: Set<String>
        var sheetGameId: String?
        var inline: [String: InlineResult]
    }

    struct WeekBoardEntry: Equatable {
        var id: String
        var rank: Int
        var isTied: Bool
        var weeklyWins: Int
        var weeklyLosses: Int
    }

    enum WeekWinKind: Equatable {
        case champ
        case coChamp

        func title(weekNumber: Int) -> String {
            switch self {
            case .champ: return "Week \(weekNumber) Champ"
            case .coChamp: return "Week \(weekNumber) Co-Champ"
            }
        }
    }

    struct WatchingEffect: Equatable {
        var announcement: String
        var feedback: Feedback
    }

    static func inlineResult(
        isFinal: Bool,
        isCorrect: Bool?,
        isPush: Bool,
        winTitle: String
    ) -> InlineResult? {
        guard isFinal else { return nil }
        if isPush { return .push }
        guard let isCorrect else { return nil }
        return isCorrect ? .win(title: winTitle) : .miss
    }

    static func inlineResult(
        pickResult: ESPNLiveGameCard.PickResult,
        winTitle: String
    ) -> InlineResult? {
        switch pickResult {
        case .win: return .win(title: winTitle)
        case .loss: return .miss
        case .push: return .push
        case .pending: return nil
        }
    }

    static func haptic(for inline: InlineResult) -> Feedback {
        if case .win = inline { return .success }
        return .none
    }

    static func announcement(
        inline: InlineResult,
        awayName: String,
        homeName: String,
        isNeutral: Bool
    ) -> String {
        let title: String
        switch inline {
        case .win(let winTitle): title = winTitle
        case .miss: title = "Missed"
        case .push: title = "Push"
        }
        let link = isNeutral ? "vs" : "at"
        return "\(title), \(awayName) \(link) \(homeName)"
    }

    /// Inline bounce, haptic, and announcement only when a game goes final while this row is on screen.
    static func watchingEffect(
        wasWatching: Bool,
        becameFinal: Bool,
        result: ESPNLiveGameCard.PickResult?,
        winTitle: String,
        awayName: String,
        homeName: String,
        isNeutral: Bool
    ) -> WatchingEffect? {
        guard wasWatching, becameFinal, let result else { return nil }
        guard let inline = inlineResult(pickResult: result, winTitle: winTitle) else { return nil }
        return WatchingEffect(
            announcement: announcement(
                inline: inline,
                awayName: awayName,
                homeName: homeName,
                isNeutral: isNeutral
            ),
            feedback: haptic(for: inline)
        )
    }

    /// First look, a return to the foreground, or a background update marks finals as seen and presents nothing.
    /// A later foreground update presents the first new correct pick and keeps misses inline.
    static func observe(
        games: [ObservedGame],
        previouslySeen: Set<String>,
        isFirstObservation: Bool,
        isForeground: Bool,
        absorbCurrentlyFinal: Bool,
        winTitle: String
    ) -> Observation {
        let holdBack = isFirstObservation || absorbCurrentlyFinal || !isForeground
        var seen = previouslySeen
        var inline: [String: InlineResult] = [:]
        var sheet: String?
        for game in games where game.isFinal {
            let isNew = !seen.contains(game.id)
            seen.insert(game.id)
            guard isNew, !holdBack else { continue }
            guard let result = inlineResult(
                isFinal: true,
                isCorrect: game.isCorrect,
                isPush: game.isPush,
                winTitle: winTitle
            ) else { continue }
            inline[game.id] = result
            if sheet == nil, case .win = result {
                sheet = game.id
            }
        }
        return Observation(seen: seen, sheetGameId: sheet, inline: inline)
    }

    /// Sole rank 1 on a scored week is Champ. A shared rank 1 is Co-Champ.
    /// A 0–0 record is not a win, and a week that is not scored is not a win.
    static func weekWinKind(
        entries: [WeekBoardEntry],
        userId: String,
        weekStatus: WeekStatus
    ) -> WeekWinKind? {
        guard weekStatus == .scored else { return nil }
        guard let me = entries.first(where: { $0.id == userId }), me.rank == 1 else { return nil }
        guard me.weeklyWins + me.weeklyLosses > 0 else { return nil }
        let sharesRank = entries.contains { $0.id != me.id && $0.rank == me.rank }
        return (me.isTied || sharesRank) ? .coChamp : .champ
    }

    static func shouldShowWeekWin(kind: WeekWinKind?, alreadyCelebrated: Bool) -> Bool {
        kind != nil && !alreadyCelebrated
    }

    static func recordLine(wins: Int, losses: Int) -> String {
        "\(wins)–\(losses) this week"
    }
}

/// Remembers Cover Moment games and the one-time week-win card. Keys are per league and week.
enum CelebrationStore {
    static func seenFinalsKey(groupId: String, weekId: String) -> String {
        "celebrated.seenFinals.\(groupId).\(weekId)"
    }

    static func weekWinKey(groupId: String, weekId: String) -> String {
        "celebrated.weekWin.\(groupId).\(weekId)"
    }

    static func loadSeenFinals(
        groupId: String,
        weekId: String,
        defaults: UserDefaults = .standard
    ) -> Set<String> {
        Set(defaults.stringArray(forKey: seenFinalsKey(groupId: groupId, weekId: weekId)) ?? [])
    }

    static func saveSeenFinals(
        _ ids: Set<String>,
        groupId: String,
        weekId: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(Array(ids).sorted(), forKey: seenFinalsKey(groupId: groupId, weekId: weekId))
    }

    static func hasCelebratedWeekWin(
        groupId: String,
        weekId: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: weekWinKey(groupId: groupId, weekId: weekId))
    }

    static func markWeekWinCelebrated(
        groupId: String,
        weekId: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(true, forKey: weekWinKey(groupId: groupId, weekId: weekId))
    }
}
