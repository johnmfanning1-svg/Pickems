import SwiftUI
import Charts

struct StatsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var stats: PlayerSeasonStats?
    @State private var isLoading = true

    private var career: CareerRecord? {
        guard let userId = appState.authService.currentUser?.id else { return nil }
        return appState.groupService.careerRecord(for: userId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if let stats {
                    summaryCards(stats)
                    if let career {
                        careerSection(career)
                    }
                    if !stats.weeklyRecords.isEmpty {
                        chartSection(stats)
                    }
                } else {
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "No Stats Yet",
                        message: "Stats appear after your first scored week."
                    )
                }
            }
            .padding()
        }
        .pickemsScreenBackground()
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    @ViewBuilder
    private func summaryCards(_ stats: PlayerSeasonStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(title: "Season", value: "\(stats.seasonWins)-\(stats.seasonLosses)")
            statCard(
                title: "Batting Avg",
                value: BattingAverage.formatted(wins: stats.seasonWins, losses: stats.seasonLosses)
            )
            statCard(title: "Win Streak", value: "\(stats.currentStreak) wk")
            if let weekNum = stats.bestWeekNumber,
               let wins = stats.bestWeekWins,
               let losses = stats.bestWeekLosses {
                statCard(title: "Best Week", value: "W\(weekNum): \(wins)-\(losses)")
            }
        }
    }

    private func careerSection(_ career: CareerRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Career Dynasty")
                .font(.headline)
                .foregroundStyle(PickemsColors.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard(title: "Titles", value: "\(career.titles)")
                statCard(title: "Career", value: career.recordLabel)
                statCard(title: "Seasons", value: "\(career.seasonsPlayed)")
                if let best = career.bestFinish {
                    statCard(title: "Best Finish", value: "#\(best)")
                }
            }
        }
    }

    private func chartSection(_ stats: PlayerSeasonStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Record")
                .font(.headline)
                .foregroundStyle(PickemsColors.textPrimary)

            Chart(stats.weeklyRecords) { record in
                BarMark(
                    x: .value("Week", "W\(record.week)"),
                    y: .value("Wins", record.wins)
                )
                .foregroundStyle(PickemsColors.success)
                BarMark(
                    x: .value("Week", "W\(record.week)"),
                    y: .value("Losses", record.losses)
                )
                .foregroundStyle(theme.accent)
            }
            .frame(height: 200)
            .chartYAxisLabel("Games")
        }
        .padding()
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(PickemsColors.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let group = appState.groupService.selectedGroup,
              let userId = appState.authService.currentUser?.id else { return }
        stats = try? await appState.groupService.loadPlayerSeasonStats(groupId: group.id, userId: userId)
    }
}
