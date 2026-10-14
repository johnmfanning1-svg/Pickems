import Foundation

/// Compact meta line under a Selections card: kickoff (or live/final state),
/// TV network, and team records when ESPN has them.
/// Example: `Sat 3:30 PM · ABC · UGA 5-1, BAMA 4-2`.
enum SelectionCardDetail {
    struct Input: Equatable {
        var kickoff: Date
        var status: SlateGame.GameStatus = .scheduled
        var awayScore: Int? = nil
        var homeScore: Int? = nil
        /// ESPN live clock line without the score, e.g. `2nd 7:12`.
        var liveClock: String? = nil
        var broadcastLabel: String? = nil
        var awayAbbreviation: String
        var homeAbbreviation: String
        var awayRecord: String? = nil
        var homeRecord: String? = nil
    }

    static func line(
        _ input: Input,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var parts: [String] = [stateText(input, locale: locale, timeZone: timeZone)]
        if input.status == .scheduled, let network = input.broadcastLabel?.trimmingCharacters(in: .whitespaces), !network.isEmpty {
            parts.append(network)
        }
        if let away = input.awayRecord, let home = input.homeRecord {
            parts.append("\(input.awayAbbreviation) \(away), \(input.homeAbbreviation) \(home)")
        }
        return parts.joined(separator: " · ")
    }

    static func stateText(
        _ input: Input,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        switch input.status {
        case .scheduled:
            return kickoffText(input.kickoff, locale: locale, timeZone: timeZone)
        case .inProgress:
            var text = "Live"
            if let away = input.awayScore, let home = input.homeScore {
                text += " \(input.awayAbbreviation) \(away)–\(input.homeAbbreviation) \(home)"
            }
            if let clock = input.liveClock?.trimmingCharacters(in: .whitespaces), !clock.isEmpty, clock != "Live" {
                text += " · \(clock)"
            }
            return text
        case .final:
            if let away = input.awayScore, let home = input.homeScore {
                return "Final \(input.awayAbbreviation) \(away)–\(input.homeAbbreviation) \(home)"
            }
            return "Final"
        }
    }

    /// `Sat 3:30 PM` in the user's time zone and locale.
    static func kickoffText(
        _ kickoff: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, timeZone: timeZone)
            .weekday(.abbreviated)
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
        style.timeZone = timeZone
        return kickoff.formatted(style)
    }
}
