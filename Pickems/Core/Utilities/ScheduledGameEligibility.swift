import Foundation

/// Postponed, canceled, suspended, and delayed games decode as `.scheduled`
/// with a disruption label. Status alone would leave them in Upcoming,
/// bulk import, Selections, and Pickems.
enum ScheduledGameEligibility {
    static func hasDisruptionLabel(_ statusLabel: String?) -> Bool {
        ESPNService.canonicalDisruptionLabel(statusLabel) != nil
    }

    /// Game Browse "Upcoming" and scheduled bulk import.
    static func isUpcoming(status: SlateGame.GameStatus, statusLabel: String?) -> Bool {
        status == .scheduled && canSelectOrPick(statusLabel: statusLabel)
    }

    /// A future kickoff does not make a disrupted game selectable or pickable.
    /// Kickoff and week locks stay separate gates.
    static func canSelectOrPick(statusLabel: String?) -> Bool {
        !hasDisruptionLabel(statusLabel)
    }

    /// Live scoreboard wins when that event is already loaded, including a nil
    /// label after a delay clears. Otherwise use the browse scoreboard.
    static func resolvedStatusLabel(
        liveCardPresent: Bool,
        liveLabel: String?,
        espnLabel: String?
    ) -> String? {
        if liveCardPresent { return liveLabel }
        return espnLabel
    }

    static func gamesEligibleForScheduledImport(_ games: [ESPNGame]) -> [ESPNGame] {
        games.filter { isUpcoming(status: $0.status, statusLabel: $0.statusLabel) }
    }

    /// Slate games the member must pick. Disrupted games stay on the slate
    /// but are not required to submit.
    static func requiredPickIds(
        slateGameIds: some Sequence<String>,
        ineligibleGameIds: Set<String>
    ) -> Set<String> {
        Set(slateGameIds).subtracting(ineligibleGameIds)
    }

    static func picksCover(requiredGameIds: Set<String>, pickedGameIds: Set<String>) -> Bool {
        requiredGameIds.isSubset(of: pickedGameIds)
    }

    /// Nil when every game can be selected. Otherwise the banner copy.
    static func selectionRejectionMessage(for games: [ESPNGame]) -> String? {
        let blocked = games.filter { hasDisruptionLabel($0.statusLabel) }
        guard !blocked.isEmpty else { return nil }
        return rejectionMessage(for: blocked)
    }

    static func rejectionMessage(for games: [ESPNGame]) -> String {
        let lines = games.map { game in
            let label = ESPNService.canonicalDisruptionLabel(game.statusLabel) ?? "Unavailable"
            return "\(SelectionKickoffGate.matchupLabel(game)) is \(label.lowercased())"
        }
        let names = LeagueWeekRecapGenerator.joinNames(lines)
        if names == "Someone" {
            return "That game can't be selected or picked."
        }
        return "\(names) and can't be selected or picked."
    }
}
