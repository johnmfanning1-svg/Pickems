import SwiftUI

struct LiveGameRow: View {
    let card: ESPNLiveGameCard

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
        case .loss: return PickemsColors.accent
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(title: title, subtitle: subtitle, help: help)

            if games.isEmpty {
                Text("No games this week.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .padding(.horizontal)
                    .accessibilityLabel("No games this week")
            } else {
                ForEach(games.prefix(8)) { card in
                    LiveGameRow(card: card)
                        .padding(.horizontal)
                }
            }
        }
    }
}
