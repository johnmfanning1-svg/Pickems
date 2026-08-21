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
    var nominatedEventIds: Set<String> = []
    var nominatorNamesByEventId: [String: String] = [:]
    let onSelect: (ESPNGame) -> Void

    @State private var searchText = ""
    @State private var filter: GameBrowseFilter = .all
    @State private var slateFilter: GameSlateFilter = .all
    @State private var loadedGames: [ESPNGame]
    @State private var loading: Bool
    @State private var loadError: String?

    init(
        games: [ESPNGame],
        nominatedEventIds: Set<String> = [],
        nominatorNamesByEventId: [String: String] = [:],
        onSelect: @escaping (ESPNGame) -> Void
    ) {
        self.games = games
        self.nominatedEventIds = nominatedEventIds
        self.nominatorNamesByEventId = nominatorNamesByEventId
        self.onSelect = onSelect
        _loadedGames = State(initialValue: games)
        _loading = State(initialValue: games.isEmpty)
    }

    private var favoriteTeamId: String? {
        appState.authService.currentUser?.favoriteTeamId
    }

    private var board: [ESPNGame] { loadedGames }

    private var filteredGames: [ESPNGame] {
        let base = board
            .filter { matchesSearch($0) }
            .filter { matchesFilter($0) }
            .filter { matchesSlateFilter($0) }
        return base.sorted { lhs, rhs in
            let lFav = isFavoriteGame(lhs)
            let rFav = isFavoriteGame(rhs)
            if lFav != rFav { return lFav && !rFav }
            if lhs.isTop25 != rhs.isTop25 { return lhs.isTop25 && !rhs.isTop25 }
            return lhs.kickoff < rhs.kickoff
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    filterBar
                    slateFilterBar
                    PickemsSearchField(text: $searchText, prompt: "Search teams")
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if let fav = filteredGames.first(where: isFavoriteGame) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(theme.accent)
                        Text("Your team is on the board — \(fav.awayTeamAbbreviation) \(fav.matchupSeparator) \(fav.homeTeamAbbreviation)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                List(filteredGames) { game in
                    let isNominated = nominatedEventIds.contains(game.espnEventId)
                    let nominatorName = nominatorNamesByEventId[game.espnEventId]
                    Button {
                        onSelect(game)
                    } label: {
                        GameBrowseRow(
                            game: game,
                            isFavoriteHighlight: isFavoriteGame(game),
                            isNominated: isNominated,
                            nominatorName: nominatorName
                        )
                    }
                    .opacity(isNominated ? 0.45 : 1)
                    .disabled(isNominated)
                    .allowsHitTesting(!isNominated)
                    .accessibilityRemoveTraits(isNominated ? .isButton : [])
                    .listRowBackground(PickemsColors.cardBackground)
                }
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 24, for: .scrollContent)
                .overlay {
                    if loading, board.isEmpty {
                        ProgressView("Loading games…")
                            .tint(theme.accent)
                    } else if filteredGames.isEmpty {
                        ContentUnavailableView(
                            "No Games Found",
                            systemImage: "magnifyingglass",
                            description: Text(loadError ?? emptyMessage)
                        )
                    }
                }
            }
            .background(PickemsColors.background)
            .navigationTitle("Select Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Text(loading && board.isEmpty ? "Loading" : "\(filteredGames.count) of \(board.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }
            .task { await refreshBoard() }
        }
    }

    private func refreshBoard() async {
        loading = loadedGames.isEmpty && games.isEmpty
        do {
            let fetched: [ESPNGame]
            if let week = appState.groupService.currentWeek {
                fetched = try await ESPNService.shared.fetchScoreboard(for: week)
            } else {
                let weekInfo = try await ESPNService.shared.currentWeek()
                let app = CFBWeekCalendar.resolve(espn: weekInfo)
                fetched = try await ESPNService.shared.fetchScoreboard(
                    week: app.espnWeekNumber,
                    seasonType: weekInfo.seasonType
                ).matching(seasonYear: app.seasonYear, appWeekNumber: app.weekNumber)
            }
            loadedGames = fetched
            loadError = nil
            appState.picksViewModel.espnGames = fetched
        } catch is CancellationError {
            return
        } catch {
            if board.isEmpty {
                loadError = "Couldn't load this week's games. Close and try again."
            }
        }
        loading = false
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
                            .padding(.vertical, 8)
                            .background(filter == option ? theme.accent : PickemsColors.cardBackground)
                            .foregroundStyle(filter == option ? theme.onAccent : PickemsColors.textPrimary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var slateFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                slateChip("All", selected: slateFilter == .all) {
                    slateFilter = .all
                }
                slateChip("Top 25", selected: slateFilter == .top25) {
                    slateFilter = .top25
                }
                ForEach(ESPNConferenceCatalog.fbs) { conference in
                    slateChip(
                        conference.shortName,
                        selected: slateFilter == .conference(id: conference.id)
                    ) {
                        slateFilter = .conference(id: conference.id)
                    }
                }
            }
        }
    }

    private func slateChip(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? theme.accent : PickemsColors.cardBackground)
                .foregroundStyle(selected ? theme.onAccent : PickemsColors.textPrimary)
                .clipShape(Capsule())
        }
    }

    private var emptyMessage: String {
        if !searchText.isEmpty {
            return "No games match \"\(searchText)\"."
        }
        switch slateFilter {
        case .top25:
            return "No Top 25 games this week."
        case .conference(let id):
            let name = ESPNConferenceCatalog.conference(id: id)?.shortName ?? "conference"
            return "No \(name) games this week."
        case .all:
            break
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

    private func matchesSlateFilter(_ game: ESPNGame) -> Bool {
        switch slateFilter {
        case .all: return true
        case .top25: return game.isTop25
        case .conference(let id):
            return game.homeConferenceId == id || game.awayConferenceId == id
        }
    }
}

struct GameBrowseRow: View {
    let game: ESPNGame
    var isFavoriteHighlight: Bool = false
    var isNominated: Bool = false
    var nominatorName: String? = nil
    @Environment(\.themePalette) private var theme

    var body: some View {
        Group {
            if isNominated {
                rowContent
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(game.awayTeamAbbreviation) \(game.isNeutralSite ? "versus" : "at") \(game.homeTeamAbbreviation), already selected by \(nominatorName ?? "another member")"
                    )
                    .accessibilityRemoveTraits(.isButton)
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            if isFavoriteHighlight {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(theme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    teamBadge(
                        abbr: game.awayTeamAbbreviation,
                        logo: game.awayTeamLogoURL,
                        rank: game.awayCuratedRank,
                        caption: "Away"
                    )

                    VStack(spacing: 2) {
                        Text(game.matchupSeparator)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }

                    teamBadge(
                        abbr: game.homeTeamAbbreviation,
                        logo: game.homeTeamLogoURL,
                        rank: game.homeCuratedRank,
                        caption: "Home"
                    )
                }

                if isNominated, let nominatorName {
                    Text(nominatorName == "the slate"
                          ? "Already on the slate"
                          : "Selected by \(nominatorName)")
                        .font(.caption2)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let spread = game.spreadDisplayLabel {
                    Text(spread)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(theme.accent)
                } else {
                    Text("No line")
                        .font(.caption2)
                        .foregroundStyle(PickemsColors.textSecondary)
                }

                if isNominated {
                    StatusBadge(text: "Taken", color: PickemsColors.textSecondary)
                } else {
                    statusLabel
                }

                Text(game.kickoffMetaLine)
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

    private func teamBadge(abbr: String, logo: String?, rank: Int?, caption: String) -> some View {
        VStack(spacing: 2) {
            TeamMark(logoURL: logo, abbreviation: abbr, rank: rank, size: 36)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(PickemsColors.textSecondary)
        }
        .frame(minWidth: 44)
    }
}
