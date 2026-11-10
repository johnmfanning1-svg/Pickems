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

    /// Nil only when the viewer is on neither board. One missing scope stays on
    /// the card as a dash so the other row still shows.
    static func summary(
        weekly: Member?,
        weeklyBoard: [Member],
        season: Member?,
        seasonBoard: [Member]
    ) -> Display? {
        guard weekly != nil || season != nil else { return nil }
        return display(
            weekly: weekly,
            weeklyBoard: weeklyBoard,
            season: season,
            seasonBoard: seasonBoard
        )
    }

    static func display(
        weekly: Member?,
        weeklyBoard: [Member],
        season: Member?,
        seasonBoard: [Member]
    ) -> Display {
        let weeklyRecord = recordStat(
            member: weekly,
            label: "This Week",
            present: { "Week \($0.wins) to \($0.losses)" },
            missing: "Week unavailable"
        )
        let seasonRecord = recordStat(
            member: season,
            label: "Season",
            present: { "season \($0.wins) to \($0.losses)" },
            missing: "Season unavailable"
        )
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
            weeklyRecord.accessibility,
            seasonRecord.accessibility,
            weeklyRank.accessibility,
            seasonRank.accessibility,
        ].joined(separator: ", ")
        return Display(
            weeklyRecord: weeklyRecord.stat,
            seasonRecord: seasonRecord.stat,
            weeklyRank: weeklyRank.stat,
            seasonRank: seasonRank.stat,
            accessibilityLabel: accessibility
        )
    }

    private struct SpokenStat {
        var stat: Stat
        var accessibility: String
    }

    private static func recordStat(
        member: Member?,
        label: String,
        present: (Member) -> String,
        missing: String
    ) -> SpokenStat {
        guard let member else {
            return SpokenStat(
                stat: Stat(value: unavailableRank, label: label),
                accessibility: missing
            )
        }
        return SpokenStat(
            stat: Stat(value: record(member.wins, member.losses), label: label),
            accessibility: present(member)
        )
    }

    private struct RankParts {
        var stat: Stat
        var accessibility: String
    }

    private static func rankStat(
        member: Member?,
        board: [Member],
        label: String,
        scope: String
    ) -> RankParts {
        guard let member else {
            return RankParts(
                stat: Stat(value: unavailableRank, label: label),
                accessibility: "No \(scope) rank yet"
            )
        }
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
            ? "Tied for \(spokenScope) rank \(member.rank)"
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
