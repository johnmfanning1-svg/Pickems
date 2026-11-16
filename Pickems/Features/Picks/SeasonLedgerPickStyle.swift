import SwiftUI

enum SeasonLedgerPickStyle {
    static func fill(for status: PickBoardStatus) -> Color {
        switch status {
        case .covering: return PickemsColors.covering
        case .trailing: return PickemsColors.warning
        case .won: return PickemsColors.success
        case .lost: return PickemsColors.lost
        case .push: return PickemsColors.ledgerPush
        case .none, .pending: return PickemsColors.cardBackground
        }
    }

    static func foreground(for status: PickBoardStatus) -> Color {
        switch status {
        case .covering: return PickemsColors.onCovering
        case .trailing: return PickemsColors.onWarning
        case .won: return PickemsColors.onSuccess
        case .lost: return PickemsColors.onLost
        case .push: return PickemsColors.onLedgerPush
        case .none, .pending: return PickemsColors.textPrimary
        }
    }
}

enum SeasonLedgerMembers {
    static func ordered(_ members: [GroupMember], currentUserId: String?) -> [GroupMember] {
        members.sorted { lhs, rhs in
            let leftOwn = lhs.id == currentUserId
            let rightOwn = rhs.id == currentUserId
            if leftOwn != rightOwn { return leftOwn && !rightOwn }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func shortName(_ member: GroupMember, currentUserId: String?) -> String {
        if member.id == currentUserId { return "You" }
        let parts = member.displayName.split(separator: " ")
        if let first = parts.first { return String(first) }
        return member.displayName
    }
}

enum SeasonLedgerGameCopy {
    static func matchup(_ game: SlateGame, showsSpreads: Bool) -> String {
        let away = game.awayTeamAbbreviation
        let home = game.homeTeamAbbreviation
        if showsSpreads, let side = game.favoredSide {
            switch side {
            case .away: return "\(away)* @ \(home)"
            case .home: return "\(away) @ \(home)*"
            }
        }
        return "\(away) @ \(home)"
    }

    static func scoreLine(_ game: SlateGame) -> String {
        guard let away = game.awayScore, let home = game.homeScore else { return "—" }
        return "\(away)–\(home)"
    }

    static func coverLabel(_ game: SlateGame, pickMode: PickMode) -> String {
        guard game.status == .final,
              let home = game.homeScore,
              let away = game.awayScore else { return "—" }
        guard let covered = game.coveredTeamId(homeScore: home, awayScore: away, pickMode: pickMode) else {
            return "Push"
        }
        if covered == game.homeTeamId { return game.homeTeamAbbreviation }
        if covered == game.awayTeamId { return game.awayTeamAbbreviation }
        return "—"
    }

    static func pickAbbreviation(game: SlateGame, pickedTeamId: String?) -> String {
        guard let pickedTeamId, !pickedTeamId.isEmpty else { return "—" }
        if pickedTeamId == game.homeTeamId { return game.homeTeamAbbreviation }
        if pickedTeamId == game.awayTeamId { return game.awayTeamAbbreviation }
        return "PICK"
    }
}