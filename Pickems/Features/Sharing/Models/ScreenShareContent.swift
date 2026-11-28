import CoreGraphics
import Foundation

/// Share payloads for leaderboard, Season Ledger, and league Pickems chart cards.
enum ScreenShareContent: Equatable, Sendable {
    case leaderboard(LeaderboardShareModel)
    case seasonLedger(SeasonLedgerShareModel)
    case pickemsChart(PickemsChartShareModel)

    var leagueName: String {
        switch self {
        case .leaderboard(let model): return model.leagueName
        case .seasonLedger(let model): return model.leagueName
        case .pickemsChart(let model): return model.leagueName
        }
    }

    var contextLabel: String {
        switch self {
        case .leaderboard(let model):
            return "\(model.periodLabel) leaderboard"
        case .seasonLedger:
            return "Season Ledger"
        case .pickemsChart(let model):
            return "\(model.periodLabel) League Pickems"
        }
    }

    var groupId: String? {
        switch self {
        case .leaderboard(let model): return model.groupId
        case .seasonLedger(let model): return model.groupId
        case .pickemsChart(let model): return model.groupId
        }
    }

    var caption: String {
        ScreenShareTextBuilder.caption(
            leagueName: leagueName,
            contextLine: contextLabel,
            groupId: groupId
        )
    }
}

struct LeaderboardShareModel: Equatable, Sendable {
    let groupId: String
    let leagueName: String
    let periodLabel: String
    let rows: [ShareLeaderboardRow]
    let omittedCount: Int
}

struct SeasonLedgerShareModel: Equatable, Sendable {
    let groupId: String
    let leagueName: String
    let columns: [ShareLedgerMemberColumn]
    let weeks: [ShareLedgerWeekRow]
    let seasonTotals: [ShareLedgerWLPair]
    let gamesBack: [String]
    let omittedMemberCount: Int
    let memberColumnWidth: CGFloat
    let weekColumnWidth: CGFloat
}

struct PickemsChartShareModel: Equatable, Sendable {
    let groupId: String
    let leagueName: String
    let periodLabel: String
    let columns: [ShareChartMemberColumn]
    let games: [ShareChartGameRow]
    let stillToPlay: ShareStillToPlayStrip?
    let omittedMemberCount: Int
    let omittedGameCount: Int
    let pickMode: PickMode
    let showsSpreads: Bool
    let gameColumnWidth: CGFloat
    let memberColumnWidth: CGFloat
}

struct ShareStillToPlayStrip: Equatable, Sendable {
    let chips: [String]
    let picksHiddenNote: String?
}

struct ShareLeaderboardRow: Equatable, Sendable {
    let rank: Int
    let displayName: String
    let avatarColorHex: String
    let wins: Int
    let losses: Int
    let caption: String
    let isViewer: Bool
}

struct ShareLedgerMemberColumn: Equatable, Sendable {
    let shortName: String
    let isViewer: Bool
}

struct ShareLedgerWeekRow: Equatable, Sendable {
    let title: String
    let records: [ShareLedgerWLPair]
}

struct ShareLedgerWLPair: Equatable, Sendable {
    let wins: Int
    let losses: Int
}

struct ShareChartMemberColumn: Equatable, Sendable {
    let shortName: String
    let isViewer: Bool
}

struct ShareChartGameRow: Equatable, Sendable {
    let matchup: String
    let cells: [ShareChartCell]
}

struct ShareChartCell: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case pick(String, PickBoardStatus)
        case locked
        case empty
    }

    let kind: Kind
}

extension ScreenShareContent {
    static func makeLeaderboard(
        groupId: String,
        leagueName: String,
        scope: LeaderboardScope.Scope,
        entries: [StandingEntry],
        viewerId: String?,
        leaderWins: Int?
    ) -> ScreenShareContent? {
        guard !entries.isEmpty else { return nil }
        let layout = ShareCardLayout.leaderboard(
            entries: entries,
            scope: scope,
            viewerId: viewerId,
            leaderWins: leaderWins
        )
        let model = LeaderboardShareModel(
            groupId: groupId,
            leagueName: leagueName,
            periodLabel: ShareCardLayout.leaderboardPeriodLabel(scope: scope),
            rows: layout.rows,
            omittedCount: layout.omittedCount
        )
        return .leaderboard(model)
    }

    static func makeSeasonLedger(
        groupId: String,
        leagueName: String,
        data: SeasonLedgerSeasonData,
        members: [GroupMember],
        currentUserId: String?
    ) -> ScreenShareContent? {
        guard !data.weeks.isEmpty, !members.isEmpty else { return nil }
        let layout = ShareCardLayout.seasonLedger(
            data: data,
            members: members,
            currentUserId: currentUserId
        )
        let model = SeasonLedgerShareModel(
            groupId: groupId,
            leagueName: leagueName,
            columns: layout.columns,
            weeks: layout.weeks,
            seasonTotals: layout.seasonTotals,
            gamesBack: layout.gamesBack,
            omittedMemberCount: layout.omittedMemberCount,
            memberColumnWidth: layout.memberColumnWidth,
            weekColumnWidth: layout.weekColumnWidth
        )
        return .seasonLedger(model)
    }

    static func makePickemsChart(
        groupId: String,
        leagueName: String,
        periodLabel: String,
        members: [GroupMember],
        games: [SlateGame],
        picksByUserId: [String: UserPick],
        hiddenGameIds: Set<String>,
        pickMode: PickMode,
        currentUserId: String?,
        liveCards: [String: ESPNLiveGameCard] = [:]
    ) -> ScreenShareContent? {
        guard !members.isEmpty, !games.isEmpty else { return nil }
        let layout = ShareCardLayout.pickemsChart(
            members: members,
            games: games,
            picksByUserId: picksByUserId,
            hiddenGameIds: hiddenGameIds,
            pickMode: pickMode,
            currentUserId: currentUserId,
            liveCards: liveCards
        )
        let model = PickemsChartShareModel(
            groupId: groupId,
            leagueName: leagueName,
            periodLabel: periodLabel,
            columns: layout.columns,
            games: layout.games,
            stillToPlay: layout.stillToPlay,
            omittedMemberCount: layout.omittedMemberCount,
            omittedGameCount: layout.omittedGameCount,
            pickMode: pickMode,
            showsSpreads: pickMode.showsSpreads,
            gameColumnWidth: layout.metrics.leadColumnWidth,
            memberColumnWidth: layout.metrics.memberColumnWidth
        )
        return .pickemsChart(model)
    }
}