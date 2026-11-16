import SwiftUI

struct SeasonLedgerDetailedView: View {
    let data: SeasonLedgerSeasonData
    let members: [GroupMember]
    let currentUserId: String?

    @State private var expandedWeekIds: Set<String> = []

    private let matchupWidth: CGFloat = 112
    private let metaWidth: CGFloat = 44
    private let pickWidth: CGFloat = 44
    private var pinnedMetaWidth: CGFloat { matchupWidth + metaWidth * 3 }

    private var scrollsMembers: Bool {
        SeasonLedgerMemberTableLayout.usesSharedHorizontalScroll(memberCount: members.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
            detailedLegend
            ScrollView(.vertical) {
                SeasonLedgerSplitMemberScroll(
                    memberCount: members.count,
                    memberBandWidth: pickWidth,
                    leadingWidth: pinnedMetaWidth,
                    rowSpacing: 4
                ) {
                    leadingTableColumn
                } memberBand: {
                    memberTableColumn
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

    private var leadingTableColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            leadingHeaderLabels
            ForEach(data.weeks) { board in
                weekLeadingBlock(board)
            }
        }
    }

    private var leadingHeaderLabels: some View {
        HStack(spacing: 0) {
            Text("Matchup")
                .frame(width: matchupWidth, alignment: .leading)
            Text("Spread")
                .frame(width: metaWidth)
            Text("Score")
                .frame(width: metaWidth)
            Text("Cover")
                .frame(width: metaWidth)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(PickemsColors.textPrimary)
        .frame(height: 52)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func weekLeadingBlock(_ board: SeasonLedgerWeekBoard) -> some View {
        let expanded = expandedWeekIds.contains(board.id)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                PickemsHaptics.selection()
                toggleWeek(board.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                    Text(SeasonLedgerWeekTitle.rowTitle(for: board.week))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(PickemsColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 32)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(board.games) { game in
                        gameLeadingRow(game, board: board)
                        Divider().overlay(PickemsColors.hairline)
                    }
                    weekTotalsLeadingRow(board)
                }
                .background(PickemsColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func gameLeadingRow(_ game: SlateGame, board: SeasonLedgerWeekBoard) -> some View {
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
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private func weekTotalsLeadingRow(_ board: SeasonLedgerWeekBoard) -> some View {
        Text("\(SeasonLedgerWeekTitle.rowTitle(for: board.week)) Totals")
            .font(.caption.weight(.bold))
            .foregroundStyle(PickemsColors.progressGold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(PickemsColors.progressGold.opacity(0.12))
    }

    private var memberTableColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            memberHeaderRow
            ForEach(data.weeks) { board in
                weekMemberBlock(board)
            }
        }
    }

    private var memberHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(members) { member in
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
                .frame(width: scrollsMembers ? pickWidth : nil)
                .frame(maxWidth: scrollsMembers ? nil : .infinity)
                .padding(.vertical, 4)
                .background(
                    member.id == currentUserId
                        ? PickemsColors.defaultAccent.opacity(0.1)
                        : Color.clear
                )
            }
        }
        .frame(height: 52)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func weekMemberBlock(_ board: SeasonLedgerWeekBoard) -> some View {
        let expanded = expandedWeekIds.contains(board.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ForEach(members) { member in
                    let wins = board.recordsByMemberId[member.id]?.wins ?? 0
                    Text("\(wins)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .frame(width: scrollsMembers ? pickWidth : nil)
                        .frame(maxWidth: scrollsMembers ? nil : .infinity)
                        .frame(height: 32)
                }
            }

            if expanded {
                VStack(spacing: 0) {
                    ForEach(board.games) { game in
                        HStack(spacing: 0) {
                            ForEach(members) { member in
                                pickChip(game: game, board: board, member: member)
                                    .frame(width: scrollsMembers ? pickWidth : nil)
                                    .frame(maxWidth: scrollsMembers ? nil : .infinity)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider().overlay(PickemsColors.hairline)
                    }
                    HStack(spacing: 0) {
                        ForEach(members) { member in
                            let wins = board.recordsByMemberId[member.id]?.wins ?? 0
                            Text("\(wins)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(PickemsColors.progressGold)
                                .frame(width: scrollsMembers ? pickWidth : nil)
                                .frame(maxWidth: scrollsMembers ? nil : .infinity)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(PickemsColors.progressGold.opacity(0.12))
                }
                .background(PickemsColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
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
                .frame(height: 28)
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
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(SeasonLedgerPickStyle.fill(for: status))
                )
                .accessibilityLabel(
                    "\(member.displayName) picked \(abbr == "—" ? "nothing" : abbr), \(status.label(for: board.pickMode))"
                )
        }
    }

    private func toggleWeek(_ weekId: String) {
        if expandedWeekIds.contains(weekId) {
            expandedWeekIds.remove(weekId)
        } else {
            expandedWeekIds.insert(weekId)
        }
    }
}