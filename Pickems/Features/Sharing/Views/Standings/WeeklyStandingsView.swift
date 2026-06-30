import SwiftUI

struct WeeklyStandingsView: View {
    @State private var result = DemoData.weeklyResult

    var body: some View {
        NavigationStack {
            List {
                Section("Your Week") {
                    LabeledContent("League", value: result.leagueName)
                    LabeledContent("Week", value: "\(result.week)")
                    LabeledContent("Record", value: result.recordText)
                    LabeledContent("Rank", value: result.placementText)
                    if let delta = result.tiebreakerDelta {
                        LabeledContent("Tiebreaker", value: "\(delta >= 0 ? "+" : "")\(delta)")
                    }
                }

                Section {
                    ShareResultsButton(source: .weekly(result))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                    SmackTalkButton(
                        context: SmackTalkIntegration.context(
                            userId: result.userId,
                            displayName: result.displayName,
                            leagueId: SmackTalkDemoData.leagueId,
                            leagueName: result.leagueName,
                            season: result.season,
                            week: result.week
                        ),
                        weeklyResult: result,
                        label: "Open Week \(result.week) Smack Talk"
                    )
                } footer: {
                    Text("Share results or jump into this week's league smack talk.")
                }
            }
            .navigationTitle("Week \(result.week)")
        }
    }
}

#if DEBUG
struct WeeklyStandingsView_Previews: PreviewProvider {
    static var previews: some View {
        SmackTalkBootstrap {
            WeeklyStandingsView()
                .environmentObject(XAuthService())
        }
    }
}
#endif
