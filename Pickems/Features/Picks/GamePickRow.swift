import SwiftUI

extension GamePickRowPresentation.PickResultTone {
    var color: Color {
        switch self {
        case .success: return PickemsColors.success
        case .lost: return PickemsColors.lost
        case .secondary: return PickemsColors.textSecondary
        case .warning: return PickemsColors.warning
        }
    }
}

struct GamePickRow: View {
    let game: SlateGame
    let selectedTeamId: String?
    var isDisabled: Bool = false
    var liveCard: ESPNLiveGameCard? = nil
    var homeRank: Int? = nil
    var awayRank: Int? = nil
    var showConfidenceToggle: Bool = false
    var isConfidence: Bool = false
    var onConfidenceToggle: (() -> Void)? = nil
    /// Shown when the row is disabled because this game has locked.
    var lockedCaption: String? = nil
    var showsSpread: Bool = true
    var winResultTitle: String = "Covered"
    let onSelect: (String) -> Void
    @Environment(\.themePalette) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var watching = false
    @State private var bounceToken = 0
    @State private var successPulse = false

    private var resolvedAwayRank: Int? {
        GamePickRowPresentation.resolvedRank(explicit: awayRank, live: liveCard?.awayCuratedRank)
    }

    private var resolvedHomeRank: Int? {
        GamePickRowPresentation.resolvedRank(explicit: homeRank, live: liveCard?.homeCuratedRank)
    }

    private var displayedStatus: SlateGame.GameStatus {
        liveCard?.status ?? game.status
    }

    private var scoreColumn: GamePickRowPresentation.ComfortableScoreColumn? {
        GamePickRowPresentation.comfortableScoreColumn(
            from: GamePickRowPresentation.statusColumn(
                game: game,
                liveCard: liveCard,
                isDisabled: isDisabled
            )
        )
    }

    private var showsResultBadge: Bool {
        guard displayedStatus == .final, let result = liveCard?.pickResult else { return false }
        return result != .pending
    }

    var body: some View {
        PickemsCard(
            padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        ) {
            VStack(spacing: PickemsSpacing.xs) {
                HStack {
                    teamButton(
                        teamId: game.awayTeamId,
                        name: game.awayTeamAbbreviation,
                        logo: game.awayTeamLogoURL,
                        rank: resolvedAwayRank,
                        caption: "Away"
                    )
                    centerColumn
                    teamButton(
                        teamId: game.homeTeamId,
                        name: game.homeTeamAbbreviation,
                        logo: game.homeTeamLogoURL,
                        rank: resolvedHomeRank,
                        caption: "Home"
                    )
                }

                metaRow

                if showConfidenceToggle {
                    Button {
                        onConfidenceToggle?()
                    } label: {
                        Label(
                            isConfidence ? "Confidence pick (2x)" : "Make confidence pick",
                            systemImage: isConfidence ? "bolt.circle.fill" : "bolt.circle"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isConfidence ? theme.accent : PickemsColors.textSecondary)
                    }
                    .disabled(isDisabled)
                }

                if let lockedCaption {
                    Label(lockedCaption, systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(successPulse ? PickemsColors.success : Color.clear, lineWidth: 1.5)
                .animation(.easeOut(duration: 0.6), value: successPulse)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            watching = displayedStatus != .final
        }
        .onChange(of: watch) { old, new in
            celebrateIfNeeded(from: old, to: new)
        }
    }

    private var watch: GamePickRowPresentation.PickWatch {
        GamePickRowPresentation.PickWatch(status: displayedStatus, result: liveCard?.pickResult)
    }

    private var centerColumn: some View {
        VStack(spacing: 2) {
            Text(game.matchupSeparator)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
            if let scoreColumn {
                if !scoreColumn.score.isEmpty {
                    Text(scoreColumn.score)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(PickemsColors.textPrimary)
                        .fixedSize()
                }
                Text(scoreColumn.caption)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(scoreColumn.captionIsLive ? PickemsColors.warning : PickemsColors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var metaRow: some View {
        HStack(alignment: .center, spacing: PickemsSpacing.xs) {
            Text(game.kickoffMetaLine)
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsResultBadge, let result = liveCard?.pickResult {
                pickResultBadge(result)
            } else if showsSpread {
                LockedSpreadLabel(
                    lockedText: game.favoriteSpreadDisplay,
                    liveText: liveCard?.liveSpreadLabel,
                    isLocked: true,
                    isFinal: displayedStatus == .final,
                    font: .caption.weight(.semibold)
                )
                .multilineTextAlignment(.trailing)
            }
        }
    }

    @ViewBuilder
    private func pickResultBadge(_ result: ESPNLiveGameCard.PickResult) -> some View {
        Label(
            GamePickRowPresentation.resultBadgeTitle(result, winTitle: winResultTitle),
            systemImage: resultSymbol(result)
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(GamePickRowPresentation.pickResultTone(result).color)
        .symbolEffect(.bounce, value: reduceMotion ? 0 : bounceToken)
    }

    private func resultSymbol(_ result: ESPNLiveGameCard.PickResult) -> String {
        switch result {
        case .win: return "checkmark.circle.fill"
        case .loss: return "xmark.circle.fill"
        case .push: return "minus.circle.fill"
        case .pending: return "clock.fill"
        }
    }

    private func celebrateIfNeeded(
        from _: GamePickRowPresentation.PickWatch,
        to new: GamePickRowPresentation.PickWatch
    ) {
        if new.status != .final {
            watching = true
            return
        }
        guard watching, let result = new.result, result != .pending else { return }
        guard let effect = CelebrationPolicy.watchingEffect(
            wasWatching: true,
            becameFinal: true,
            result: result,
            winTitle: winResultTitle,
            awayName: game.awayTeamName,
            homeName: game.homeTeamName,
            isNeutral: game.isNeutralSite
        ) else {
            watching = false
            return
        }
        watching = false
        AccessibilityNotification.Announcement(effect.announcement).post()
        guard effect.feedback == .success else { return }
        PickemsHaptics.success()
        if !reduceMotion {
            bounceToken += 1
        }
        successPulse = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            successPulse = false
        }
    }

    /// Empty string is treated as no pick so a cleared Pickem can be tapped again.
    private var resolvedSelectedTeamId: String? {
        GamePickRowPresentation.resolvedSelectedTeamId(selectedTeamId)
    }

    private func teamButton(
        teamId: String,
        name: String,
        logo: String?,
        rank: Int?,
        caption: String
    ) -> some View {
        let isSelected = resolvedSelectedTeamId == teamId
        let access = GamePickRowPresentation.teamAccessibility(
            caption: caption,
            abbreviation: name,
            rank: rank,
            isSelected: isSelected,
            isDisabled: isDisabled,
            lockedCaption: lockedCaption,
            showsSpread: showsSpread
        )
        return Button {
            guard !isDisabled else { return }
            PickemsHaptics.selection()
            // Tap again to clear the Pickem only — never the slate Selection.
            onSelect(isSelected ? "" : teamId)
        } label: {
            VStack(spacing: 2) {
                TeamMark(
                    logoURL: logo,
                    abbreviation: name,
                    rank: rank,
                    size: 28,
                    showsAbbreviationFallback: false
                )
                Text(name)
                    .font(.body.weight(.semibold))
            }
            .padding(.vertical, PickemsSpacing.xs)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? theme.accent.opacity(0.22) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? theme.accent : Color.clear, lineWidth: 1.5)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .padding(PickemsSpacing.xxs)
                        .accessibilityHidden(true)
                }
            }
            .animation(.snappy(duration: 0.2), value: isSelected)
        }
        .disabled(isDisabled)
        .foregroundStyle(PickemsColors.textPrimary)
        .accessibilityLabel(access.label)
        .accessibilityAddTraits(access.isSelected ? [.isSelected] : [])
        .accessibilityHint(access.hint)
    }
}
