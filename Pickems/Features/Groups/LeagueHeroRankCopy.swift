import Foundation

/// Leagues summary card. This week and the season each get a record and a rank.
/// A 0–0 record hides the number so a join-order rank cannot read as #1.
/// Ties use the same T-# prefix as Home and Live Activity.
enum LeagueHeroRankCopy {
    struct Stat: Equatable {
        var value: String
        var label: String
    }

    struct Display: Equatable {
        var weeklyRecord: Stat
        var seasonRecord: Stat
        var weeklyRank: Stat
        var seasonRank: Stat
        var accessibilityLabel: String
    }

    /// One member as ranked on a single board (this week, or the season).
    struct Member: Equatable {
        var id: String
        var wins: Int
        var losses: Int
        var rank: Int
        var isTied: Bool
    }

    /// Em dash. Same mark Home uses when a week has no decided games.
    static let unavailableRank = "\u{2014}"

    /// Reads the record for `weeklyScope` so a weekly rank cannot sit on season wins.
    static func member(
        id: String,
        weeklyWins: Int,
        weeklyLosses: Int,
        seasonWins: Int,
        seasonLosses: Int,
        rank: Int,
        isTied: Bool,
        weeklyScope: Bool
    ) -> Member {
        Member(
            id: id,
            wins: weeklyScope ? weeklyWins : seasonWins,
            losses: weeklyScope ? weeklyLosses : seasonLosses,
            rank: rank,
            isTied: isTied
        )
    }

    static func display(
        weekly: Member,
        weeklyBoard: [Member],
        season: Member,
        seasonBoard: [Member]
    ) -> Display {
        let weeklyRank = rankStat(
            member: weekly,
            board: weeklyBoard,
            label: "This Week Rank",
            scope: "this week"
        )
        let seasonRank = rankStat(
            member: season,
            board: seasonBoard,
            label: "Season Rank",
            scope: "season"
        )
        let accessibility = [
            "Week \(weekly.wins) to \(weekly.losses)",
            "season \(season.wins) to \(season.losses)",
            weeklyRank.accessibility,
            seasonRank.accessibility,
        ].joined(separator: ", ")
        return Display(
            weeklyRecord: Stat(value: record(weekly.wins, weekly.losses), label: "This Week"),
            seasonRecord: Stat(value: record(season.wins, season.losses), label: "Season"),
            weeklyRank: weeklyRank.stat,
            seasonRank: seasonRank.stat,
            accessibilityLabel: accessibility
        )
    }

    private struct RankParts {
        var stat: Stat
        var accessibility: String
    }

    private static func rankStat(
        member: Member,
        board: [Member],
        label: String,
        scope: String
    ) -> RankParts {
        if member.wins + member.losses == 0 {
            return RankParts(
                stat: Stat(value: unavailableRank, label: label),
                accessibility: "No \(scope) rank yet"
            )
        }
        let sharesRank = board.contains { $0.id != member.id && $0.rank == member.rank }
        let tied = member.isTied || sharesRank
        let value = tied ? "T-#\(member.rank)" : "#\(member.rank)"
        let spokenScope = "\(scope.prefix(1).uppercased())\(scope.dropFirst())"
        let accessibility = tied
            ? "Tied for \(scope) rank \(member.rank)"
            : "\(spokenScope) rank \(member.rank)"
        return RankParts(
            stat: Stat(value: value, label: label),
            accessibility: accessibility
        )
    }

    private static func record(_ wins: Int, _ losses: Int) -> String {
        "\(wins)\u{2013}\(losses)"
    }
}
