import AppIntents
import WidgetKit

struct WidgetLeagueEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "League")
    static var defaultQuery = WidgetLeagueQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WidgetLeagueQuery: EntityQuery {
    func entities(for identifiers: [WidgetLeagueEntity.ID]) async throws -> [WidgetLeagueEntity] {
        PickemsAppGroup.loadLeagues()
            .filter { identifiers.contains($0.id) }
            .map { WidgetLeagueEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [WidgetLeagueEntity] {
        PickemsAppGroup.loadLeagues().map { WidgetLeagueEntity(id: $0.id, name: $0.name) }
    }

    func defaultResult() async -> WidgetLeagueEntity? {
        let leagues = PickemsAppGroup.loadLeagues()
        // A Profile pin fills the widget's league. With no pin, leave this empty so
        // the widget shows the snapshot for the league open in the app.
        guard let id = PickemsAppGroup.displayGroupId(),
              let match = leagues.first(where: { $0.id == id }) else {
            return nil
        }
        return WidgetLeagueEntity(id: match.id, name: match.name)
    }
}

struct SelectLeagueIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Pickems"
    static var description = IntentDescription("Deadline countdown, live scoreboard, and standings.")

    @Parameter(title: "League")
    var league: WidgetLeagueEntity?
}

/// Reloads timelines only. The widget does not reach the network.
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Pickems"
    static var description = IntentDescription("Reloads Pickems widgets.")
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: "PickemsStandingsWidget")
        return .result()
    }
}
