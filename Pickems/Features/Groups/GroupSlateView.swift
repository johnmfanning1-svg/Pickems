import SwiftUI

/// Leftover navigation into the weekly workspace. 3.0 uses the Selections and
/// Pickems tabs; this forwards to the same `PicksView` roots.
struct GroupSlateView: View {
    let group: PickemGroup
    let week: WeekSummary
    @Environment(AppState.self) private var appState

    var body: some View {
        PicksView(kind: week.status == .selection ? .selections : .pickems)
            .onAppear {
                appState.groupService.selectGroup(group)
                appState.groupService.selectWeek(weekId: week.id)
            }
    }
}
