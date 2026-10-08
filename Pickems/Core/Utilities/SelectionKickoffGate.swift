import Foundation

/// Whether a game can still be added to weekly Selections.
/// Kickoff at or before `now`, or a game already in progress or final, is closed.
enum SelectionKickoffGate {
    static func hasKickedOff(kickoff: Date, now: Date = Date()) -> Bool {
        kickoff <= now
    }

    static func hasKickedOff(
        kickoff: Date,
        status: SlateGame.GameStatus,
        now: Date = Date()
    ) -> Bool {
        hasKickedOff(kickoff: kickoff, now: now) || status == .inProgress || status == .final
    }

    static func hasKickedOff(_ game: ESPNGame, now: Date = Date()) -> Bool {
        hasKickedOff(kickoff: game.kickoff, status: game.status, now: now)
    }

    static func hasKickedOff(_ game: SlateGame, now: Date = Date()) -> Bool {
        hasKickedOff(kickoff: game.kickoff, status: game.status, now: now)
    }

    static func matchupLabel(away: String, home: String, separator: String) -> String {
        "\(away) \(separator) \(home)"
    }

    static func matchupLabel(_ game: ESPNGame) -> String {
        matchupLabel(
            away: game.awayTeamAbbreviation,
            home: game.homeTeamAbbreviation,
            separator: game.matchupSeparator
        )
    }

    static func matchupLabel(_ game: SlateGame) -> String {
        matchupLabel(
            away: game.awayTeamAbbreviation,
            home: game.homeTeamAbbreviation,
            separator: game.matchupSeparator
        )
    }

    static func rejectionMessage(matchups: [String]) -> String {
        let cleaned = matchups
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            return "That game has already kicked off and can't be added to Selections."
        }
        let names = LeagueWeekRecapGenerator.joinNames(cleaned)
        let verb = cleaned.count == 1 ? "has" : "have"
        return "\(names) \(verb) already kicked off and can't be added to Selections."
    }
}
