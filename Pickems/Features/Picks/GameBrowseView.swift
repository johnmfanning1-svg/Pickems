import SwiftUI

enum GameBrowseFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case scheduled = "Upcoming"
    case live = "Live"
    case final = "Final"

    var id: String { rawValue }
}

struct GameBrowseView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme
    let games: [ESPNGame]
    let onSelect: (ESPNGame) -> Void

    @State private var searchText = ""
    @State private var filter: GameBrowseFilter = .all

    private var favoriteTeamId: String? {
        appState.authService.currentUser?.favoriteTeamId
    }

    private var filteredGames: [ESPNGame] {
        let base = games
            .filter { matchesSearch($0) }
            .filter { matchesFilter($0) }
        return base.sorted { lhs, rhs in
            let lFav = isFavoriteGame(lhs)
            let rFav = isFavoriteGame(rhs)
            if lFav != rFav { return lFav && !rFav }
            return lhs.kickoff < rhs.kickoff
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                if let fav = filteredGames.first(where: isFavoriteGame) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(theme.accent)
                        Text("Your team is on the board — \(fav.awayTeamAbbreviation) @ \(fav.homeTeamAbbreviation)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                List(filteredGames) { game in
                    Button {
                        onSelect(game)
                    } label: {
                        GameBrowseRow(game: game, isFavoriteHighlight: isFavoriteGame(game))
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                }
                .scrollContentBackground(.hidden)
                .overlay {
                    if filteredGames.isEmpty {
                        ContentUnavailableView(
                            "No Games Found",
                            systemImage: "magnifyingglass",
                            description: Text(emptyMessage)
                        )
                    }
                }
            }
            .background(PickemsColors.background)
            .navigationTitle("Select Game")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search teams")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Text("\(filteredGames.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }
        }
    }

    private func isFavoriteGame(_ game: ESPNGame) -> Bool {
        guard let favoriteTeamId else { return false }
        return game.homeTeamId == favoriteTeamId || game.awayTeamId == favoriteTeamId
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GameBrowseFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        Text(option.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(filter == option ? theme.accent : PickemsColors.cardBackground)
                            .foregroundStyle(filter == option ? theme.onAccent : PickemsColors.textPrimary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var emptyMessage: String {
        if !searchText.isEmpty {
            return "No games match \"\(searchText)\"."
        }
        switch filter {
        case .all: return "No games available this week."
        case .scheduled: return "No upcoming games."
        case .live: return "No games in progress right now."
        case .final: return "No completed games yet."
        }
    }

    private func matchesSearch(_ game: ESPNGame) -> Bool {
        guard !searchText.isEmpty else { return true }
        let query = searchText.lowercased()
        return game.homeTeamName.lowercased().contains(query)
            || game.awayTeamName.lowercased().contains(query)
            || game.homeTeamAbbreviation.lowercased().contains(query)
            || game.awayTeamAbbreviation.lowercased().contains(query)
    }

    private func matchesFilter(_ game: ESPNGame) -> Bool {
        switch filter {
        case .all: return true
        case .scheduled: return game.status == .scheduled
        case .live: return game.status == .inProgress
        case .final: return game.status == .final
        }
    }
}

struct GameBrowseRow: View {
    let game: ESPNGame
    var isFavoriteHighlight: Bool = false
    @Environment(\.themePalette) private var theme

    var body: some View {
        HStack(spacing: 12) {
            if isFavoriteHighlight {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(theme.accent)
            }
            teamBadge(
                abbr: game.awayTeamAbbreviation,
                logo: game.awayTeamLogoURL
            )

            VStack(spacing: 2) {
                Text("@")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
            }

            teamBadge(
                abbr: game.homeTeamAbbreviation,
                logo: game.homeTeamLogoURL
            )

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusLabel
                if let spread = game.spreadDisplayLabel {
                    Text(spread)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
                Text(game.kickoff.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(PickemsColors.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch game.status {
        case .scheduled:
            Text("Scheduled")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
        case .inProgress:
            HStack(spacing: 4) {
                Circle()
                    .fill(PickemsColors.warning)
                    .frame(width: 6, height: 6)
                if let away = game.awayScore, let home = game.homeScore {
                    Text("\(away)-\(home)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PickemsColors.warning)
                } else {
                    Text("Live")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PickemsColors.warning)
                }
            }
        case .final:
            if let away = game.awayScore, let home = game.homeScore {
                Text("Final \(away)-\(home)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
            } else {
                Text("Final")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
            }
        }
    }

    private func teamBadge(abbr: String, logo: String?) -> some View {
        VStack(spacing: 4) {
            if let logo, let url = URL(string: logo) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(abbr).font(.caption.bold())
                }
                .frame(width: 36, height: 36)
            } else {
                Text(abbr)
                    .font(.headline)
                    .foregroundStyle(PickemsColors.textPrimary)
            }
        }
        .frame(width: 44)
    }
}
