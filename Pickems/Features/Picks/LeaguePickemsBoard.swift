import SwiftUI

/// Games as rows, members as columns. Cell color tracks live cover vs final result.
struct LeaguePickemsBoard: View {
    let members: [GroupMember]
    let games: [SlateGame]
    let picksByUserId: [String: UserPick]
    var liveCards: [String: ESPNLiveGameCard] = [:]
    var teamRanks: TeamRankLookup = .empty
    var currentUserId: String?
    var allowsExpand: Bool = true
    var isExpandedLayout: Bool = false
    /// Rolling lock: games that have not kicked off yet. Cells show a lock, not a pick.
    var hiddenGameIds: Set<String> = []

    @Environment(\.themePalette) private var theme
    @State private var isExpanded = false

    private var gameColumnWidth: CGFloat { isExpandedLayout ? 168 : 152 }
    private var pickColumnWidth: CGFloat { isExpandedLayout ? 88 : 76 }
    private let headerHeight: CGFloat = 44
    private let rowHeight: CGFloat = 76

    private var columns: [GroupMember] {
        members.sorted { lhs, rhs in
            let leftOwn = lhs.id == currentUserId
            let rightOwn = rhs.id == currentUserId
            if leftOwn != rightOwn { return leftOwn && !rightOwn }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            colorKey
            board
            chartFootnote
        }
        .fullScreenCover(isPresented: $isExpanded) {
            LeaguePickemsExpandedBoard(
                members: members,
                games: games,
                picksByUserId: picksByUserId,
                liveCards: liveCards,
                teamRanks: teamRanks,
                currentUserId: currentUserId,
                hiddenGameIds: hiddenGameIds
            )
        }
    }

    private var colorKey: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Color key")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                Spacer(minLength: 8)
                if allowsExpand {
                    Button {
                        isExpanded = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .padding(8)
                            .background(PickemsColors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .accessibilityLabel("Expand chart")
                    .accessibilityHint("Opens a landscape fullscreen view of the league Pickems chart")
                }
            }
            HStack(spacing: 8) {
                keyChip("Trailing", fill: PickemsColors.warning, ink: .black)
                keyChip("Covering", fill: PickemsColors.covering, ink: .white)
                keyChip("Won", fill: PickemsColors.success, ink: .black)
                keyChip("Lost", fill: PickemsColors.lost, ink: .white)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func keyChip(_ title: String, fill: Color, ink: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(fill)
            .clipShape(Capsule())
            .accessibilityLabel(title)
    }

    private var chartFootnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("* Favored team — the spread applies to this team.")
            Text("The lock is the Pickems line used for scoring. The number in parentheses is ESPN’s live line, for reference.")
        }
        .font(.caption2)
        .foregroundStyle(PickemsColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var board: some View {
        HStack(alignment: .top, spacing: 0) {
            gameColumn
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    memberHeaderRow
                    ForEach(games) { game in
                        pickRow(for: game)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("League Pickems board. Games as rows, members as columns.")
    }

    private var gameColumn: some View {
        VStack(spacing: 0) {
            Text("Game")
                .font(.caption.weight(.bold))
                .foregroundStyle(PickemsColors.textSecondary)
                .padding(.horizontal, 10)
                .frame(width: gameColumnWidth, height: headerHeight, alignment: .leading)
                .background(PickemsColors.cardBackground)
            ForEach(games) { game in
                gameLabel(game)
                    .padding(.horizontal, 10)
                    .frame(width: gameColumnWidth, height: rowHeight, alignment: .leading)
                    .background(PickemsColors.cardBackground)
            }
        }
    }

    private var memberHeaderRow: some View {
        HStack(spacing: 1) {
            ForEach(columns) { member in
                Text(columnTitle(for: member))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PickemsColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(width: pickColumnWidth, height: headerHeight)
                    .background(PickemsColors.cardBackground)
                    .accessibilityLabel(member.displayName)
            }
        }
    }

    private func pickRow(for game: SlateGame) -> some View {
        HStack(spacing: 1) {
            ForEach(columns) { member in
                pickCell(game: game, member: member)
            }
        }
    }

    private func gameLabel(_ game: SlateGame) -> some View {
        let live = liveCards[game.espnEventId]
        let status = live?.status ?? game.status
        let awayRank = live?.awayCuratedRank ?? teamRanks.rank(for: game.awayTeamId)
        let homeRank = live?.homeCuratedRank ?? teamRanks.rank(for: game.homeTeamId)
        let matchup = TeamDisplay.matchupLabel(
            awayAbbreviation: game.awayTeamAbbreviation,
            awayRank: awayRank,
            homeAbbreviation: game.homeTeamAbbreviation,
            homeRank: homeRank,
            separator: game.matchupSeparator,
            favoredSide: game.favoredSide
        )
        return VStack(alignment: .leading, spacing: 2) {
            Text(matchup)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            LockedSpreadLabel(
                lockedText: game.favoriteSpreadDisplay,
                liveText: live?.liveSpreadLabel,
                isLocked: true
            )
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            Text(gameStatusLine(game: game, live: live, status: status))
                .font(.caption2)
                .foregroundStyle(status == .inProgress ? PickemsColors.warning : PickemsColors.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gameAccessibilityLabel(
            game: game,
            matchup: matchup,
            live: live,
            status: status
        ))
    }

    private func gameAccessibilityLabel(
        game: SlateGame,
        matchup: String,
        live: ESPNLiveGameCard?,
        status: SlateGame.GameStatus
    ) -> String {
        var parts = [matchup]
        if let side = game.favoredSide {
            let name = side == .home ? game.homeTeamAbbreviation : game.awayTeamAbbreviation
            parts.append("\(name) is favored — the spread applies to this team")
        }
        parts.append(
            SpreadLineCopy.accessibilityLabel(
                locked: game.favoriteSpreadDisplay,
                live: live?.liveSpreadLabel,
                isLocked: true
            )
        )
        parts.append(
            gameStatusLine(game: game, live: live, status: status, compactKickoff: false)
        )
        return parts.joined(separator: ". ")
    }

    private func gameStatusLine(
        game: SlateGame,
        live: ESPNLiveGameCard?,
        status: SlateGame.GameStatus,
        compactKickoff: Bool = true
    ) -> String {
        switch status {
        case .inProgress:
            if let detail = live?.statusDetail, !detail.isEmpty {
                return detail
            }
            if let away = live?.awayScore ?? game.awayScore,
               let home = live?.homeScore ?? game.homeScore {
                return "Live \(away)–\(home)"
            }
            return "Live"
        case .final:
            if let away = live?.awayScore ?? game.awayScore,
               let home = live?.homeScore ?? game.homeScore {
                return "Final \(away)–\(home)"
            }
            return "Final"
        case .scheduled:
            return GameKickoffLine.make(
                kickoff: game.kickoff,
                broadcastLabel: game.broadcastLabel,
                dateStyle: compactKickoff ? .compactMonthDay : .abbreviated
            )
        }
    }

    @ViewBuilder
    private func pickCell(game: SlateGame, member: GroupMember) -> some View {
        if hiddenGameIds.contains(game.id) {
            Image(systemName: "lock.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(PickemsColors.textSecondary)
                .frame(width: pickColumnWidth, height: rowHeight)
                .background(PickemsColors.cardBackground)
                .accessibilityLabel("\(member.displayName) pick hidden until kickoff")
        } else {
            let pickedId = picksByUserId[member.id]?.picks[game.id]
            let live = liveCards[game.espnEventId]
            let status = ScoringEngine.pickBoardStatus(
                pickedTeamId: pickedId,
                game: game,
                homeScore: live?.homeScore ?? game.homeScore,
                awayScore: live?.awayScore ?? game.awayScore,
                status: live?.status ?? game.status
            )
            let label = pickAbbreviation(game: game, pickedTeamId: pickedId)
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(status.foreground)
                .frame(width: pickColumnWidth, height: rowHeight)
                .background(status.fill)
                .accessibilityLabel(
                    "\(member.displayName) picked \(label == "—" ? "nothing" : label), \(status.label)"
                )
        }
    }

    private func pickAbbreviation(game: SlateGame, pickedTeamId: String?) -> String {
        guard let pickedTeamId, !pickedTeamId.isEmpty else { return "—" }
        if pickedTeamId == game.homeTeamId { return game.homeTeamAbbreviation }
        if pickedTeamId == game.awayTeamId { return game.awayTeamAbbreviation }
        return "PICK"
    }

    private func columnTitle(for member: GroupMember) -> String {
        if member.id == currentUserId { return "You" }
        let parts = member.displayName.split(separator: " ")
        if let first = parts.first { return String(first) }
        return member.displayName
    }
}

/// Landscape fullscreen chart. Portrait lock is restored on dismiss.
struct LeaguePickemsExpandedBoard: View {
    let members: [GroupMember]
    let games: [SlateGame]
    let picksByUserId: [String: UserPick]
    var liveCards: [String: ESPNLiveGameCard] = [:]
    var teamRanks: TeamRankLookup = .empty
    var currentUserId: String?
    var hiddenGameIds: Set<String> = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LeaguePickemsBoard(
                    members: members,
                    games: games,
                    picksByUserId: picksByUserId,
                    liveCards: liveCards,
                    teamRanks: teamRanks,
                    currentUserId: currentUserId,
                    allowsExpand: false,
                    isExpandedLayout: true,
                    hiddenGameIds: hiddenGameIds
                )
                .padding()
            }
            .pickemsScreenBackground()
            .navigationTitle("League Pickems")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .statusBarHidden(true)
        .onAppear { InterfaceOrientationLock.set(.landscape) }
        .onDisappear { InterfaceOrientationLock.set(.portrait) }
    }
}

private extension PickBoardStatus {
    var fill: Color {
        switch self {
        case .covering: return PickemsColors.covering
        case .trailing: return PickemsColors.warning
        case .won: return PickemsColors.success
        case .lost: return PickemsColors.lost
        case .none, .pending, .push: return PickemsColors.cardBackground
        }
    }

    var foreground: Color {
        switch self {
        case .covering, .lost: return .white
        case .trailing, .won: return .black
        case .none, .pending, .push: return PickemsColors.textPrimary
        }
    }
}
