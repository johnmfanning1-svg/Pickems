import SwiftUI

struct SeasonStandingsView: View {
    @State private var standing = DemoData.seasonStanding

    var body: some View {
        NavigationStack {
            List {
                Section("Final Standing") {
                    LabeledContent("League", value: standing.leagueName)
                    LabeledContent("Season", value: "\(standing.season)")
                    LabeledContent("Rank", value: standing.placementText)
                    LabeledContent("Points", value: "\(standing.totalPoints)")
                    LabeledContent("Weekly Wins", value: "\(standing.weeklyWins)")
                    if let bestWeek = standing.bestWeek, let record = standing.bestWeekRecord {
                        LabeledContent("Best Week", value: "Week \(bestWeek) (\(record))")
                    }
                }

                Section {
                    ShareResultsButton(source: .season(standing))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("Post your end-of-year results by text or X and let the league know who really won.")
                }
            }
            .navigationTitle("Season \(standing.season)")
        }
    }
}

#if DEBUG
struct SeasonStandingsView_Previews: PreviewProvider {
    static var previews: some View {
        SeasonStandingsView()
            .environmentObject(XAuthService())
    }
}
#endif
