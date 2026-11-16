import SwiftUI

struct SeasonLedgerDetailedView: View {
    let data: SeasonLedgerSeasonData
    let members: [GroupMember]
    let currentUserId: String?
    let pickMode: PickMode

    @State private var expandedWeekIds: Set<String> = []

    private let matchupWidth: CGFloat = 112
    private let metaWidth: CGFloat = 44
    private let pickWidth: CGFloat = 44
    private var scrollsMembers: Bool { members.count > 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
            detailedLegend
            detailedHeaderRow
                .padding(.bottom, 4)
            ScrollView {
                LazyVStack(spacing: PickemsSpacing.sm) {
                    ForEach(data.weeks) { board in
                        weekSection(board)
                    }
                }
            }
        }
        .onAppear {
            if expandedWeekIds.isEmpty {
                expandedWeekIds = defaultExpandedWeekIds
            }
        }
    }

    private var defaultExpandedWeekIds: Set<String> {
        let scored = data.weeks.filter { $0.week.status == .scored && !$0.games.isEmpty }
        return Set(scored.suffix(2).map(\.id))
    }

    private var detailedLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                legendDot(PickemsColors.success, "Won")
                legendDot(PickemsColors.lost, "Lost")
                legendDot(PickemsColors.ledgerPush, "Push")
            }
            Text("* Favored team — the spread applies to this team.")
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
        }
        .font(.caption.weight(.semibold))
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(PickemsColors.textSecondary)
        }
    }

    private var detailedHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Matchup")
                .frame(width: matchupWidth, alignment: .leading)
            Text("Spread")
                .frame(width: metaWidth)
            Text("Score")
                .frame(width: metaWidth)
            Text("Cover")
                .frame(width: metaWidth)
            memberPickColumns { member in
                VStack(spacing: 2) {
                    Text(SeasonLedgerMembers.shortName(member, currentUserId: currentUserId))
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    let season = data.seasonRecord(for: member.id)
                    Text("\(season.wins)–\(season.losses)–\(season.pushes)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                .frame(width: pickWidth)
                .padding(.vertical, 4)
                .background(
                    member.id == currentUserId
                        ? PickemsColors.defaultAccent.opacity(0.1)
                        : Color.clear
                )
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(PickemsColors.textPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func weekSection(_ board: SeasonLedgerWeekBoard) -> some View {
        let isExpanded = expandedWeekIds.contains(board.id)
        DisclosureGroup(
            isExpanded: Binding(
                get: { isExpanded },
                set: { expanded in
                    if expanded { expandedWeekIds.insert(board.id) }
                    else { expandedWeekIds.remove(board.id) }
                }
            ),
            content: {
                VStack(spacing: 0) {
                    ForEach(board.games) { game in
                        gameRow(game, board: board)
                        Divider().overlay(PickemsColors.hairline)
                    }
                    weekTotalsRow(board)
                }
                .background(PickemsColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            },
            label: {
                collapsedWeekHeader(board)
            }
        )
        .tint(PickemsColors.textPrimary)
    }

    private func collapsedWeekHeader(_ board: SeasonLedgerWeekBoard) -> some View {
        HStack {
            Text(SeasonLedgerWeekTitle.rowTitle(for: board.week))
                .font(.subheadline.weight(.semibold))
            Spacer()
            memberPickColumns { member in
                let wins = board.recordsByMemberId[member.id]?.wins ?? 0
                Text("\(wins)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .frame(width: pickWidth)
            }
        }
        .accessibilityLabel("\(SeasonLedgerWeekTitle.rowTitle(for: board.week)). Collapsible week section.")
    }

    private func gameRow(_ game: SlateGame, board: SeasonLedgerWeekBoard) -> some View {
        HStack(spacing: 0) {
            Text(SeasonLedgerGameCopy.matchup(game, showsSpreads: board.pickMode.showsSpreads))
                .font(.caption.weight(.semibold))
                .frame(width: matchupWidth, alignment: .leading)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(board.pickMode.showsSpreads ? game.favoriteSpreadDisplay : "—")
                .font(.caption2.monospacedDigit())
                .frame(width: metaWidth)
            Text(SeasonLedgerGameCopy.scoreLine(game))
                .font(.caption2.monospacedDigit())
                .frame(width: metaWidth)
            Text(SeasonLedgerGameCopy.coverLabel(game, pickMode: board.pickMode))
                .font(.caption2.weight(.semibold))
                .frame(width: metaWidth)
            memberPickColumns { member in
                pickChip(game: game, board: board, member: member)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

  @ViewBuilder
    private func pickChip(game: SlateGame, board: SeasonLedgerWeekBoard, member: GroupMember) -> some View {
        if !SeasonLedgerPrivacy.mayShowPick(
            gameId: game.id,
            memberId: member.id,
            viewerId: currentUserId,
            hiddenGameIds: board.hiddenGameIds
        ) {
            Image(systemName: "lock.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(PickemsColors.textSecondary)
                .frame(width: pickWidth, height: 28)
                .accessibilityLabel("\(member.displayName), pick hidden until kickoff")
        } else {
            let pickedId = board.picksByUserId[member.id]?.picks[game.id]
            let status = SeasonLedgerAggregator.pickCellStatus(
                game: game,
                pickedTeamId: pickedId,
                pickMode: board.pickMode
            )
            let abbr = SeasonLedgerGameCopy.pickAbbreviation(game: game, pickedTeamId: pickedId)
            Text(abbr)
                .font(.caption2.weight(.bold))
                .foregroundStyle(SeasonLedgerPickStyle.foreground(for: status))
                .frame(width: pickWidth, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(SeasonLedgerPickStyle.fill(for: status))
                )
                .accessibilityLabel(
                    "\(member.displayName) picked \(abbr == "—" ? "nothing" : abbr), \(status.label(for: board.pickMode))"
                )
        }
    }

    private func weekTotalsRow(_ board: SeasonLedgerWeekBoard) -> some View {
        HStack(spacing: 0) {
            Text("\(SeasonLedgerWeekTitle.rowTitle(for: board.week)) Totals")
                .font(.caption.weight(.bold))
                .foregroundStyle(PickemsColors.progressGold)
                .frame(width: matchupWidth + metaWidth * 3, alignment: .leading)
            memberPickColumns { member in
                let wins = board.recordsByMemberId[member.id]?.wins ?? 0
                Text("\(wins)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(PickemsColors.progressGold)
                    .frame(width: pickWidth)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(PickemsColors.progressGold.opacity(0.12))
    }

    @ViewBuilder
    private func memberPickColumns<Content: View>(@ViewBuilder content: @escaping (GroupMember) -> Content) -> some View {
        if scrollsMembers {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(members) { member in
                        content(member)
                    }
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(members) { member in
                    content(member)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}