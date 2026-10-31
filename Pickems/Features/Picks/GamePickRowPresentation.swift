import Foundation

/// Shared pick-row rules for Comfortable and Dense. Views render these values; they do not
/// reimplement selection, rank, spread, status, or VoiceOver copy.
enum GamePickRowPresentation {
    static func resolvedSelectedTeamId(_ selectedTeamId: String?) -> String? {
        guard let selectedTeamId, !selectedTeamId.isEmpty else { return nil }
        return selectedTeamId
    }

    static func resolvedRank(explicit: Int?, live: Int?) -> Int? {
        explicit ?? live
    }

    struct TeamAccessibility: Equatable {
        let label: String
        let hint: String
        let isSelected: Bool
    }

    static func teamAccessibility(
        caption: String,
        abbreviation: String,
        rank: Int?,
        isSelected: Bool,
        isDisabled: Bool,
        lockedCaption: String?,
        showsSpread: Bool
    ) -> TeamAccessibility {
        let label = "\(caption) \(TeamDisplay.rankedLabel(abbreviation: abbreviation, rank: rank))"
        let hint: String
        if isDisabled {
            hint = lockedCaption ?? "Pickems are locked"
        } else if isSelected {
            hint = "Clear \(abbreviation) pick"
        } else {
            let how = showsSpread ? "against the spread" : "to win"
            hint = "Select \(abbreviation) \(how)"
        }
        return TeamAccessibility(label: label, hint: hint, isSelected: isSelected)
    }

    /// Right-hand status for a dense row. Comfortable still lays these facts out as a card.
    enum StatusColumn: Equatable {
        case scheduled(time: String)
        case live(score: String, period: String)
        case final(label: String, result: ESPNLiveGameCard.PickResult?)
        case locked(time: String)
    }

    static func statusColumn(
        game: SlateGame,
        liveCard: ESPNLiveGameCard?,
        isDisabled: Bool,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> StatusColumn {
        let status = liveCard?.status ?? game.status
        let away = liveCard?.awayScore ?? game.awayScore
        let home = liveCard?.homeScore ?? game.homeScore
        switch status {
        case .final:
            let label: String
            if let away, let home {
                label = "F \(scoreLine(away: away, home: home))"
            } else {
                label = "F"
            }
            return .final(label: label, result: liveCard?.pickResult)
        case .inProgress:
            let score: String
            if let away, let home {
                score = scoreLine(away: away, home: home)
            } else {
                score = ""
            }
            return .live(score: score, period: compactPeriod(from: liveCard?.statusDetail ?? ""))
        case .scheduled:
            let time = kickoffClock(kickoff: game.kickoff, now: now, calendar: calendar)
            if isDisabled {
                return .locked(time: time)
            }
            return .scheduled(time: time)
        }
    }

    /// VoiceOver for the status cluster. Team buttons keep their own labels.
    /// Scheduled and locked rows speak the same kickoff line Comfortable shows.
    static func statusAccessibilityLabel(
        column: StatusColumn,
        kickoffMetaLine: String,
        statusDetail: String?,
        lockedCaption: String?
    ) -> String {
        var parts: [String] = []
        switch column {
        case .scheduled:
            parts.append(kickoffMetaLine)
        case .live:
            if let statusDetail, !statusDetail.isEmpty {
                parts.append(statusDetail)
            }
            parts.append(kickoffMetaLine)
        case .final(_, let result):
            if let statusDetail, !statusDetail.isEmpty {
                parts.append(statusDetail)
            }
            if let result {
                parts.append(resultSpokenName(result))
            }
            parts.append(kickoffMetaLine)
        case .locked:
            parts.append(lockedCaption ?? "Locked at kickoff")
            parts.append(kickoffMetaLine)
        }
        return parts.joined(separator: ". ")
    }

    static func resultSpokenName(_ result: ESPNLiveGameCard.PickResult) -> String {
        switch result {
        case .win: return "Win"
        case .loss: return "Loss"
        case .push: return "Push"
        case .pending: return "Pending"
        }
    }

    /// Signed Pickems line for the favorite's pill (`-3.5`). Nil for the dog, pick'em, or Straight Up.
    static func spreadSuffix(game: SlateGame, teamId: String, showsSpread: Bool) -> String? {
        guard showsSpread else { return nil }
        let line = game.gradingLine
        guard abs(line.spread) > 0, line.teamId == teamId else { return nil }
        return game.spreadLabel(for: teamId)
    }

    static func pillTitle(abbreviation: String, rank: Int?, spreadSuffix: String?) -> String {
        let name = TeamDisplay.rankedLabel(abbreviation: abbreviation, rank: rank)
        guard let spreadSuffix, !spreadSuffix.isEmpty else { return name }
        return "\(name) \(spreadSuffix)"
    }

    static func lineInfoMessage(locked: String, live: String?, isFinal: Bool) -> String? {
        guard let live else { return nil }
        return SpreadLineCopy.infoMessage(locked: locked, live: live, isFinal: isFinal)
    }

    static func scoreLine(away: Int, home: Int) -> String {
        "\(away)\u{2013}\(home)"
    }

    /// `12:00` today. Other days prefix the weekday (`Sat 12:00`).
    static func kickoffClock(kickoff: Date, now: Date, calendar: Calendar) -> String {
        let time = compactTime(kickoff, calendar: calendar)
        if calendar.isDate(kickoff, inSameDayAs: now) {
            return time
        }
        return "\(weekdayAbbreviation(kickoff, calendar: calendar)) \(time)"
    }

    static func compactTime(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.calendar = calendar
        return strippingMeridiem(date.formatted(style))
    }

    static func weekdayAbbreviation(_ date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)
        let symbols = calendar.shortWeekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    /// Drops `AM` / `PM` so the dense clock matches `12:00`. Keeps a 24-hour clock as-is.
    static func strippingMeridiem(_ time: String) -> String {
        var result = time
        let tokens = [
            "\u{202f}AM", "\u{202f}PM",
            "\u{00a0}AM", "\u{00a0}PM",
            " AM", " PM",
            " am", " pm",
            " a.m.", " p.m.",
            "AM", "PM"
        ]
        for token in tokens {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `3rd 7:12` → `Q3`, halftime → `HT`, overtime → `OT`. Empty when the detail is only "Live".
    static func compactPeriod(from statusDetail: String) -> String {
        let stripped = ESPNLiveGameCard.strippingTrailingScore(from: statusDetail)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty { return "" }
        let lower = stripped.lowercased()
        if lower == "live" || lower == "in progress" || lower == "upcoming" { return "" }
        if lower.contains("halftime") || lower == "half" { return "HT" }
        if lower.contains("overtime") || lower.range(of: #"\bot\b"#, options: .regularExpression) != nil {
            return "OT"
        }
        if let quarter = quarterNumber(in: stripped) {
            return "Q\(quarter)"
        }
        return stripped
    }

    private static func quarterNumber(in text: String) -> String? {
        let pattern = #"^(?:q)?(\d+)(?:st|nd|rd|th)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let numberRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let number = String(text[numberRange])
        guard number == "1" || number == "2" || number == "3" || number == "4" else { return nil }
        return number
    }
}
