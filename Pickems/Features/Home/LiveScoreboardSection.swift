import SwiftUI

struct LiveGameRow: View {
    let card: ESPNLiveGameCard
    @Environment(\.themePalette) private var theme

    var body: some View {
        PickemsCard {
            HStack(spacing: 12) {
                teamColumn(
                    name: card.awayTeamAbbreviation,
                    logo: card.awayTeamLogoURL,
                    score: card.awayScore
                )

                VStack(spacing: 4) {
                    if card.status == .scheduled {
                        Text(card.kickoff.formatted(date: .omitted, time: .shortened))
                            .font(.caption.weight(.semibold))
                    } else {
                        Text(card.statusDetail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(card.status == .inProgress ? PickemsColors.warning : PickemsColors.textSecondary)
                    }
                    if let spread = card.spreadLabel {
                        Text(spread)
                            .font(.caption2)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                    if card.isSlateGame, let pick = card.userPickTeamAbbreviation {
                        HStack(spacing: 4) {
                            Text("Pick: \(pick)")
                                .font(.caption2)
                            pickResultIcon
                        }
                        .foregroundStyle(pickResultColor)
                    }
                }
                .frame(minWidth: 80)

                teamColumn(
                    name: card.homeTeamAbbreviation,
                    logo: card.homeTeamLogoURL,
                    score: card.homeScore
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        let awayScore = card.awayScore.map { "\($0)" } ?? "not started"
        let homeScore = card.homeScore.map { "\($0)" } ?? "not started"
        parts.append("\(card.awayTeamAbbreviation) \(awayScore), \(card.homeTeamAbbreviation) \(homeScore)")
        if card.status == .scheduled {
            parts.append("Kickoff \(card.kickoff.formatted(date: .abbreviated, time: .shortened))")
        } else {
            parts.append(card.statusDetail)
        }
        if let spread = card.spreadLabel {
            parts.append(spread)
        }
        if card.isSlateGame, let pick = card.userPickTeamAbbreviation {
            parts.append("Your pick: \(pick)")
            if let result = card.pickResult {
                switch result {
                case .win: parts.append("pick won")
                case .loss: parts.append("pick lost")
                case .push: parts.append("push")
                case .pending: parts.append("result pending")
                }
            }
        }
        return parts.joined(separator: ". ")
    }

    @ViewBuilder
    private var pickResultIcon: some View {
        switch card.pickResult {
        case .win: Image(systemName: "checkmark.circle.fill")
        case .loss: Image(systemName: "xmark.circle.fill")
        case .push: Image(systemName: "minus.circle.fill")
        case .pending, .none: EmptyView()
        }
    }

    private var pickResultColor: Color {
        switch card.pickResult {
        case .win: return PickemsColors.success
        case .loss: return theme.accent
        case .push: return PickemsColors.textSecondary
        case .pending, .none: return PickemsColors.warning
        }
    }

    private func teamColumn(name: String, logo: String?, score: Int?) -> some View {
        VStack(spacing: 4) {
            if let logo, let url = URL(string: logo) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(name).font(.caption.bold())
                }
                .frame(width: 32, height: 32)
            } else {
                Text(name).font(.headline)
            }
            if let score {
                Text("\(score)")
                    .font(.title3.bold())
                    .foregroundStyle(PickemsColors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct LiveScoreboardSection: View {
    let games: [ESPNLiveGameCard]
    let title: String
    var subtitle: String? = nil
    var help: HelpTopic? = nil
    /// When non-nil, shows filter chips and filters `games` before display.
    var scoreboardFilter: Binding<HomeScoreboardFilter>? = nil

    @Environment(\.themePalette) private var theme

    private var filteredGames: [ESPNLiveGameCard] {
        guard let scoreboardFilter else { return games }
        return games.filter { $0.matches(scoreboardFilter.wrappedValue) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(title: title, subtitle: subtitle, help: help)

            if scoreboardFilter != nil {
                filterBar
            }

            if filteredGames.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .padding(.horizontal)
                    .accessibilityLabel(emptyMessage)
            } else {
                ForEach(filteredGames.prefix(8)) { card in
                    LiveGameRow(card: card)
                        .padding(.horizontal)
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(.power4)
                filterChip(.top25)
                filterChip(.myPicks)
                filterChip(.groupSlate)
                filterChip(.all)
                ForEach(ESPNConferenceCatalog.fbs) { conference in
                    filterChip(.conference(id: conference.id))
                }
            }
            .padding(.horizontal)
        }
        .accessibilityLabel("Scoreboard filters")
    }

    private func filterChip(_ filter: HomeScoreboardFilter) -> some View {
        let selected = scoreboardFilter?.wrappedValue == filter
        return Button {
            PickemsHaptics.selection()
            scoreboardFilter?.wrappedValue = filter
        } label: {
            Text(filter.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected == true ? theme.accent : PickemsColors.cardBackground)
                .foregroundStyle(selected == true ? theme.onAccent : PickemsColors.textPrimary)
                .clipShape(Capsule())
        }
        .accessibilityAddTraits(selected == true ? [.isSelected] : [])
    }

    private var emptyMessage: String {
        guard let filter = scoreboardFilter?.wrappedValue else {
            return "No games this week."
        }
        switch filter {
        case .power4: return "No Power 4 games this week."
        case .top25: return "No Top 25 games this week."
        case .myPicks: return "No picks selected yet."
        case .groupSlate: return "No games on your group slate."
        case .conference(let id):
            let name = ESPNConferenceCatalog.conference(id: id)?.shortName ?? "conference"
            return "No \(name) games this week."
        case .all: return "No games this week."
        }
    }
}
