import SwiftUI

/// Comfortable cards, or the compact row when Dense is on.
/// Accessibility text sizes stay on Comfortable so team names are never crushed.
struct GamePickRowAdaptive: View {
    var isDense: Bool
    let game: SlateGame
    let selectedTeamId: String?
    var isDisabled: Bool = false
    var liveCard: ESPNLiveGameCard? = nil
    var homeRank: Int? = nil
    var awayRank: Int? = nil
    var showConfidenceToggle: Bool = false
    var isConfidence: Bool = false
    var onConfidenceToggle: (() -> Void)? = nil
    var lockedCaption: String? = nil
    var showsSpread: Bool = true
    let onSelect: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesDense: Bool {
        isDense && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        if usesDense {
            GamePickRowDense(
                game: game,
                selectedTeamId: selectedTeamId,
                isDisabled: isDisabled,
                liveCard: liveCard,
                homeRank: homeRank,
                awayRank: awayRank,
                showConfidenceToggle: showConfidenceToggle,
                isConfidence: isConfidence,
                onConfidenceToggle: onConfidenceToggle,
                lockedCaption: lockedCaption,
                showsSpread: showsSpread,
                onSelect: onSelect
            )
        } else {
            GamePickRow(
                game: game,
                selectedTeamId: selectedTeamId,
                isDisabled: isDisabled,
                liveCard: liveCard,
                homeRank: homeRank,
                awayRank: awayRank,
                showConfidenceToggle: showConfidenceToggle,
                isConfidence: isConfidence,
                onConfidenceToggle: onConfidenceToggle,
                lockedCaption: lockedCaption,
                showsSpread: showsSpread,
                onSelect: onSelect
            )
        }
    }
}

/// One compact Pickems row. Same inputs as `GamePickRow`.
struct GamePickRowDense: View {
    let game: SlateGame
    let selectedTeamId: String?
    var isDisabled: Bool = false
    var liveCard: ESPNLiveGameCard? = nil
    var homeRank: Int? = nil
    var awayRank: Int? = nil
    var showConfidenceToggle: Bool = false
    var isConfidence: Bool = false
    var onConfidenceToggle: (() -> Void)? = nil
    var lockedCaption: String? = nil
    var showsSpread: Bool = true
    let onSelect: (String) -> Void

    @Environment(\.themePalette) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var resolvedAwayRank: Int? {
        GamePickRowPresentation.resolvedRank(explicit: awayRank, live: liveCard?.awayCuratedRank)
    }

    private var resolvedHomeRank: Int? {
        GamePickRowPresentation.resolvedRank(explicit: homeRank, live: liveCard?.homeCuratedRank)
    }

    private var resolvedSelectedTeamId: String? {
        GamePickRowPresentation.resolvedSelectedTeamId(selectedTeamId)
    }

    private var isFinal: Bool {
        (liveCard?.status ?? game.status) == .final
    }

    private var lineInfoMessage: String? {
        guard showsSpread else { return nil }
        return GamePickRowPresentation.lineInfoMessage(
            locked: game.favoriteSpreadDisplay,
            live: liveCard?.liveSpreadLabel,
            isFinal: isFinal
        )
    }

    /// Favorite that should sit next to the line-info button. Nil for pick'em and Straight Up.
    private var favoriteTeamId: String? {
        guard showsSpread else { return nil }
        let line = game.gradingLine
        guard abs(line.spread) > 0 else { return nil }
        return line.teamId
    }

    var body: some View {
        Group {
            if dynamicTypeSize >= .xxxLarge {
                ViewThatFits(in: .horizontal) {
                    singleLine
                    stacked
                }
            } else {
                singleLine
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var singleLine: some View {
        HStack(spacing: 4) {
            matchup
            Spacer(minLength: 6)
            statusColumn
            confidenceButton
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 48)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 2) {
            matchup
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                statusColumn
                confidenceButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var matchup: some View {
        HStack(spacing: 4) {
            teamPill(
                teamId: game.awayTeamId,
                abbreviation: game.awayTeamAbbreviation,
                rank: resolvedAwayRank,
                caption: "Away"
            )
            if favoriteTeamId == game.awayTeamId {
                lineInfo
            }
            Text(game.matchupSeparator)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
                .accessibilityHidden(true)
            teamPill(
                teamId: game.homeTeamId,
                abbreviation: game.homeTeamAbbreviation,
                rank: resolvedHomeRank,
                caption: "Home"
            )
            if favoriteTeamId != game.awayTeamId {
                lineInfo
            }
        }
    }

    @ViewBuilder
    private var lineInfo: some View {
        if let lineInfoMessage {
            SpreadLineInfoButton(message: lineInfoMessage, isFinal: isFinal, containsHitTarget: true)
        }
    }

    private func teamPill(
        teamId: String,
        abbreviation: String,
        rank: Int?,
        caption: String
    ) -> some View {
        let isSelected = resolvedSelectedTeamId == teamId
        let access = GamePickRowPresentation.teamAccessibility(
            caption: caption,
            abbreviation: abbreviation,
            rank: rank,
            isSelected: isSelected,
            isDisabled: isDisabled,
            lockedCaption: lockedCaption,
            showsSpread: showsSpread
        )
        let title = GamePickRowPresentation.pillTitle(
            abbreviation: abbreviation,
            rank: rank,
            spreadSuffix: GamePickRowPresentation.spreadSuffix(
                game: game,
                teamId: teamId,
                showsSpread: showsSpread
            )
        )
        return Button {
            guard !isDisabled else { return }
            PickemsHaptics.selection()
            onSelect(isSelected ? "" : teamId)
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .foregroundStyle(PickemsColors.textPrimary)
                .background(
                    isSelected ? theme.accent.opacity(0.3) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? theme.accent : Color.white.opacity(0.14), lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(access.label)
        .accessibilityAddTraits(access.isSelected ? [.isSelected] : [])
        .accessibilityHint(access.hint)
    }

    private var statusColumn: some View {
        let column = GamePickRowPresentation.statusColumn(
            game: game,
            liveCard: liveCard,
            isDisabled: isDisabled
        )
        return HStack(spacing: 4) {
            switch column {
            case .scheduled(let time):
                Text(time)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
            case .locked(let time):
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .accessibilityHidden(true)
                Text(time)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
            case .live(let score, let period):
                Text(liveStatusText(score: score, period: period))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PickemsColors.warning)
            case .final(let label, let result):
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PickemsColors.textPrimary)
                if let result {
                    resultIcon(result)
                }
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            GamePickRowPresentation.statusAccessibilityLabel(
                column: column,
                kickoffMetaLine: game.kickoffMetaLine,
                statusDetail: liveCard?.statusDetail,
                lockedCaption: lockedCaption
            )
        )
    }

    private func liveStatusText(score: String, period: String) -> String {
        switch (score.isEmpty, period.isEmpty) {
        case (true, true): return "Live"
        case (false, true): return score
        case (true, false): return period
        case (false, false): return "\(score) \(period)"
        }
    }

    @ViewBuilder
    private func resultIcon(_ result: ESPNLiveGameCard.PickResult) -> some View {
        switch result {
        case .win:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.success)
        case .loss:
            Image(systemName: "xmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.accent)
        case .push:
            Image(systemName: "minus.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
        case .pending:
            Image(systemName: "clock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.warning)
        }
    }

    @ViewBuilder
    private var confidenceButton: some View {
        if showConfidenceToggle {
            Button {
                guard !isDisabled else { return }
                onConfidenceToggle?()
            } label: {
                Image(systemName: isConfidence ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isConfidence ? theme.accent : PickemsColors.textSecondary)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityLabel(isConfidence ? "Confidence pick (2x)" : "Make confidence pick")
        }
    }
}

// MARK: - Previews

#Preview("Dense states") {
    ScrollView {
        DensePreviewContainer {
            ForEach(Array(GamePickRowPreviewData.states.enumerated()), id: \.element.id) { index, sample in
                GamePickRowDense(
                    game: sample.game,
                    selectedTeamId: sample.previewSelection,
                    isDisabled: sample.isDisabled,
                    liveCard: sample.liveCard,
                    homeRank: sample.homeRank,
                    awayRank: sample.awayRank,
                    showConfidenceToggle: sample.kind == .confidence,
                    isConfidence: sample.kind == .confidence,
                    lockedCaption: sample.lockedCaption,
                    showsSpread: sample.showsSpread,
                    onSelect: { _ in }
                )
                if index < GamePickRowPreviewData.states.count - 1 {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .padding()
    }
    .pickemsScreenBackground()
}

#Preview("Dense 22 games") {
    ScrollView {
        DenseSlatePreview()
            .padding()
    }
    .pickemsScreenBackground()
}

#Preview("Comfortable 22 games") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(GamePickRowPreviewData.slate(count: 22)) { sample in
                GamePickRow(
                    game: sample.game,
                    selectedTeamId: sample.index.isMultiple(of: 2) ? sample.game.homeTeamId : nil,
                    liveCard: sample.liveCard,
                    homeRank: sample.homeRank,
                    awayRank: sample.awayRank,
                    showConfidenceToggle: sample.kind == .confidence,
                    isConfidence: sample.kind == .confidence,
                    showsSpread: sample.showsSpread,
                    onSelect: { _ in }
                )
            }
        }
        .padding()
    }
    .pickemsScreenBackground()
}

private struct DenseSlatePreview: View {
    private let samples = GamePickRowPreviewData.slate(count: 22)

    var body: some View {
        DensePreviewContainer {
            ForEach(Array(samples.enumerated()), id: \.element.id) { index, sample in
                GamePickRowDense(
                    game: sample.game,
                    selectedTeamId: sample.index.isMultiple(of: 2) ? sample.game.homeTeamId : nil,
                    isDisabled: sample.isDisabled,
                    liveCard: sample.liveCard,
                    homeRank: sample.homeRank,
                    awayRank: sample.awayRank,
                    lockedCaption: sample.lockedCaption,
                    showsSpread: sample.showsSpread,
                    onSelect: { _ in }
                )
                if index < samples.count - 1 {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
    }
}

private struct DensePreviewContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct GamePickRowPreviewSample: Identifiable {
    enum Kind {
        case scheduled, live, finalWon, finalLost, push, locked, disabled, confidence, ranked, longAbbreviation, noSpread
    }

    let index: Int
    let kind: Kind
    let game: SlateGame
    let liveCard: ESPNLiveGameCard?
    let homeRank: Int?
    let awayRank: Int?
    let showsSpread: Bool
    let lockedCaption: String?

    var id: String { game.id }

    var isDisabled: Bool { kind == .locked || kind == .disabled }

    var previewSelection: String? {
        switch kind {
        case .scheduled, .finalLost, .push, .confidence, .ranked:
            return game.homeTeamId
        case .live, .finalWon, .longAbbreviation, .noSpread:
            return game.awayTeamId
        case .locked, .disabled:
            return game.homeTeamId
        }
    }
}

private enum GamePickRowPreviewData {
    static let states: [GamePickRowPreviewSample] = [
        .scheduled, .live, .finalWon, .finalLost, .push, .locked, .disabled, .confidence, .ranked, .longAbbreviation, .noSpread
    ].enumerated().map { index, kind in
        make(index: index, kind: kind)
    }

    static func slate(count: Int) -> [GamePickRowPreviewSample] {
        (0..<count).map { index in
            let kind: GamePickRowPreviewSample.Kind = {
                switch index {
                case 0: return .live
                case 1: return .finalWon
                case 2: return .finalLost
                case 3: return .push
                case 4: return .locked
                default: return .scheduled
                }
            }()
            return make(index: index, kind: kind, varyKickoff: true)
        }
    }

    private static func make(
        index: Int,
        kind: GamePickRowPreviewSample.Kind,
        varyKickoff: Bool = false
    ) -> GamePickRowPreviewSample {
        let key = varyKickoff ? "slate-\(index)" : kindKey(kind)
        let away = abbreviations(for: kind, index: index).away
        let home = abbreviations(for: kind, index: index).home
        let kickoff = Calendar.current.date(byAdding: .hour, value: varyKickoff ? index * 3 : 3, to: Date()) ?? Date()
        let status: SlateGame.GameStatus = {
            switch kind {
            case .live, .disabled: return .inProgress
            case .finalWon, .finalLost, .push: return .final
            default: return .scheduled
            }
        }()
        let scores: (away: Int, home: Int)? = {
            switch kind {
            case .live, .disabled: return (21, 14)
            case .finalWon: return (41, 9)
            case .finalLost: return (17, 31)
            case .push: return (24, 27)
            default: return nil
            }
        }()
        let spread: Double = kind == .noSpread ? 0 : (kind == .ranked ? 3.5 : 1.5)
        let homeTeamId = "\(key)-home"
        let awayTeamId = "\(key)-away"
        let game = SlateGame(
            id: key,
            espnEventId: key,
            homeTeamId: homeTeamId,
            homeTeamName: home,
            homeTeamAbbreviation: home,
            homeTeamLogoURL: nil,
            awayTeamId: awayTeamId,
            awayTeamName: away,
            awayTeamAbbreviation: away,
            awayTeamLogoURL: nil,
            spread: spread,
            spreadTeamId: homeTeamId,
            kickoff: kickoff,
            status: status,
            homeScore: scores?.home,
            awayScore: scores?.away,
            winnerTeamId: nil
        )
        return GamePickRowPreviewSample(
            index: index,
            kind: kind,
            game: game,
            liveCard: liveCard(for: kind, game: game, scores: scores),
            homeRank: kind == .ranked ? 13 : nil,
            awayRank: kind == .ranked ? 22 : nil,
            showsSpread: kind != .noSpread,
            lockedCaption: {
                switch kind {
                case .locked: return "Locked at kickoff"
                case .disabled: return "Postponed"
                default: return nil
                }
            }()
        )
    }

    private static func kindKey(_ kind: GamePickRowPreviewSample.Kind) -> String {
        switch kind {
        case .scheduled: return "scheduled"
        case .live: return "live"
        case .finalWon: return "won"
        case .finalLost: return "lost"
        case .push: return "push"
        case .locked: return "locked"
        case .disabled: return "disabled"
        case .confidence: return "confidence"
        case .ranked: return "ranked"
        case .longAbbreviation: return "long"
        case .noSpread: return "nospread"
        }
    }

    private static func abbreviations(
        for kind: GamePickRowPreviewSample.Kind,
        index: Int
    ) -> (away: String, home: String) {
        if kind == .longAbbreviation { return ("COASTAL", "NWESTERN") }
        if kind == .ranked { return ("ARIZ", "TTU") }
        let pairs = [
            ("BAY", "UCF"), ("WIS", "IOWA"), ("ALA", "AUB"), ("OSU", "MICH"),
            ("UGA", "TENN"), ("ORE", "USC"), ("PSU", "CLEM"), ("LSU", "FLA"),
            ("TEX", "OU"), ("ND", "STAN"), ("MIZ", "ARK"), ("UNC", "NCST")
        ]
        return pairs[index % pairs.count]
    }

    private static func liveCard(
        for kind: GamePickRowPreviewSample.Kind,
        game: SlateGame,
        scores: (away: Int, home: Int)?
    ) -> ESPNLiveGameCard? {
        let result: ESPNLiveGameCard.PickResult? = {
            switch kind {
            case .finalWon: return .win
            case .finalLost: return .loss
            case .push: return .push
            case .live, .disabled: return .pending
            default: return nil
            }
        }()
        let detail: String = {
            switch kind {
            case .live: return "3rd 7:12 · 21-14"
            case .disabled: return "2nd 4:05 · 21-14"
            case .finalWon: return "Final · 41-9"
            case .finalLost: return "Final · 17-31"
            case .push: return "Final · 24-27"
            default: return ""
            }
        }()
        guard result != nil || kind == .ranked else { return nil }
        let movedLine = kind == .ranked ? "TTU -6.5" : nil
        return ESPNLiveGameCard(
            id: game.id,
            espnEventId: game.espnEventId,
            awayTeamId: game.awayTeamId,
            awayTeamName: game.awayTeamName,
            awayTeamAbbreviation: game.awayTeamAbbreviation,
            awayTeamLogoURL: nil,
            homeTeamId: game.homeTeamId,
            homeTeamName: game.homeTeamName,
            homeTeamAbbreviation: game.homeTeamAbbreviation,
            homeTeamLogoURL: nil,
            awayScore: scores?.away,
            homeScore: scores?.home,
            spreadLabel: game.favoriteSpreadDisplay,
            status: game.status,
            statusDetail: detail,
            kickoff: game.kickoff,
            isSlateGame: true,
            homeCuratedRank: kind == .ranked ? 13 : nil,
            awayCuratedRank: kind == .ranked ? 22 : nil,
            homeConferenceId: nil,
            awayConferenceId: nil,
            userPickTeamAbbreviation: nil,
            pickResult: result,
            liveSpreadLabel: movedLine
        )
    }
}
