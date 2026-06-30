import SwiftUI

/// Demo shell for week-to-week league smack talk.
struct SmackTalkTabView: View {
    @EnvironmentObject private var smackTalkService: LocalSmackTalkService

    @State private var week = SmackTalkDemoData.currentWeek
    @State private var result = DemoData.weeklyResult

    private var context: SmackTalkContext {
        SmackTalkIntegration.context(
            userId: SmackTalkDemoData.currentUserId,
            displayName: SmackTalkDemoData.currentDisplayName,
            leagueId: SmackTalkDemoData.leagueId,
            leagueName: SmackTalkDemoData.leagueName,
            season: SmackTalkDemoData.season,
            week: week
        )
    }

    var body: some View {
        NavigationStack {
            WeekSmackTalkView(context: context, weeklyResult: result)
                .id(context.thread.id)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(5...8, id: \.self) { demoWeek in
                                Button("Week \(demoWeek)") {
                                    week = demoWeek
                                    result = demoWeeklyResult(for: demoWeek)
                                }
                            }

                            Divider()

                            Button("Post standings update") {
                                Task {
                                    try? await smackTalkService.postSystemMessage(
                                        text: SmackTalkIntegration.systemMessage(for: result),
                                        thread: context.thread
                                    )
                                }
                            }
                        } label: {
                            Label("Week", systemImage: "calendar")
                        }
                    }
                }
        }
    }

    private func demoWeeklyResult(for week: Int) -> WeeklyResult {
        WeeklyResult(
            id: "demo-weekly-\(week)",
            userId: SmackTalkDemoData.currentUserId,
            displayName: SmackTalkDemoData.currentDisplayName,
            week: week,
            season: SmackTalkDemoData.season,
            leagueName: SmackTalkDemoData.leagueName,
            correctPicks: result.correctPicks,
            totalPicks: result.totalPicks,
            rank: result.rank,
            totalPlayers: result.totalPlayers,
            tiebreakerDelta: result.tiebreakerDelta,
            isWeeklyWinner: result.isWeeklyWinner
        )
    }
}

#if DEBUG
struct SmackTalkTabView_Previews: PreviewProvider {
    static var previews: some View {
        SmackTalkTabView()
            .environmentObject(LocalSmackTalkService())
    }
}
#endif
