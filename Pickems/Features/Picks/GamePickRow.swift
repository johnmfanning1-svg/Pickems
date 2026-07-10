import SwiftUI

struct GamePickRow: View {
    let game: SlateGame
    let selectedTeamId: String?
    var isDisabled: Bool = false
    var liveCard: ESPNLiveGameCard? = nil
    let onSelect: (String) -> Void
    @Environment(\.themePalette) private var theme

    var body: some View {
        PickemsCard {
            VStack(spacing: 12) {
                HStack {
                    teamButton(teamId: game.awayTeamId, name: game.awayTeamAbbreviation, logo: game.awayTeamLogoURL)
                    VStack(spacing: 2) {
                        Text("@")
                            .foregroundStyle(PickemsColors.textSecondary)
                        if let live = liveCard, live.status != .scheduled {
                            Text(live.statusDetail)
                                .font(.caption2)
                                .foregroundStyle(live.status == .inProgress ? PickemsColors.warning : PickemsColors.textSecondary)
                        }
                    }
                    teamButton(teamId: game.homeTeamId, name: game.homeTeamAbbreviation, logo: game.homeTeamLogoURL)
                }

                HStack {
                    Text("Spread: \(game.spreadLabel(for: game.spreadTeamId)) \(spreadTeamAbbreviation)")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                    Spacer()
                    if let result = liveCard?.pickResult {
                        pickResultBadge(result)
                    }
                }

                Text(game.kickoff.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(PickemsColors.textSecondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func pickResultBadge(_ result: ESPNLiveGameCard.PickResult) -> some View {
        switch result {
        case .win:
            Label("Win", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.success)
        case .loss:
            Label("Loss", systemImage: "xmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.accent)
        case .push:
            Label("Push", systemImage: "minus.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
        case .pending:
            Label("Pending", systemImage: "clock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.warning)
        }
    }

    private var spreadTeamAbbreviation: String {
        game.spreadTeamId == game.homeTeamId ? game.homeTeamAbbreviation : game.awayTeamAbbreviation
    }

    private func teamButton(teamId: String, name: String, logo: String?) -> some View {
        Button {
            if !isDisabled {
                PickemsHaptics.selection()
                onSelect(teamId)
            }
        } label: {
            VStack {
                if let logo, let url = URL(string: logo) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "football.fill")
                    }
                    .frame(width: 32, height: 32)
                }
                Text(name)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(selectedTeamId == teamId ? theme.accent.opacity(0.3) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedTeamId == teamId ? theme.accent : Color.clear, lineWidth: 2)
            )
        }
        .disabled(isDisabled)
        .foregroundStyle(PickemsColors.textPrimary)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selectedTeamId == teamId ? [.isSelected] : [])
        .accessibilityHint(isDisabled ? "Picks are locked" : "Select \(name) against the spread")
    }
}
