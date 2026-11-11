import Foundation

/// Counts behind the Make Selections subtitle.
/// The Picks header and the widget snapshot both call this so the line cannot drift.
enum MemberSelectionProgress: Equatable {
    struct Counts: Equatable {
        var youMade: Int
        var youTotal: Int
        var membersDone: Int
        var memberCount: Int
        var gamesFilled: Int
        var gamesTarget: Int

        var subtitle: String {
            WidgetSelectionProgressLine.subtitle(
                youMade: youMade,
                youTotal: youTotal,
                membersDone: membersDone,
                membersTotal: memberCount,
                gamesFilled: gamesFilled,
                gamesTarget: gamesTarget
            )
        }
    }

    static func counts(
        nominations: [Nomination],
        slateEventIds: [String],
        userId: String,
        memberIds: [String],
        weekSelectionsPerMember: Int,
        rulesSelectionsPerMember: Int,
        gamesTarget: Int
    ) -> Counts {
        let perMember = weekSelectionsPerMember > 0 ? weekSelectionsPerMember : rulesSelectionsPerMember
        let youMade = nominations.filter { $0.submittedBy == userId }.count
        var byUser: [String: Int] = [:]
        for nomination in nominations {
            byUser[nomination.submittedBy, default: 0] += 1
        }
        let membersDone = memberIds.filter { (byUser[$0] ?? 0) >= perMember }.count
        let gamesFilled = Set(nominations.map(\.espnEventId) + slateEventIds).count
        return Counts(
            youMade: youMade,
            youTotal: perMember,
            membersDone: membersDone,
            memberCount: max(memberIds.count, 1),
            gamesFilled: gamesFilled,
            gamesTarget: gamesTarget
        )
    }
}
