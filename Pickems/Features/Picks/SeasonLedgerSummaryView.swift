import SwiftUI

struct SeasonLedgerSummaryView: View {
    let data: SeasonLedgerSeasonData
    let members: [GroupMember]
    let currentUserId: String?

    private let weekColumnWidth: CGFloat = 76
    private let memberPairWidth: CGFloat = 58
    private var scrollsHorizontally: Bool { members.count > 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
            summaryLegend
            tableCard
        }
    }

    private var summaryLegend: some View {
        HStack(spacing: 16) {
            legendSwatch(color: PickemsColors.success, label: "Best week")
            legendSwatch(color: PickemsColors.progressGold, label: "Tied for best")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(PickemsColors.textSecondary)
        .accessibilityElement(children: .combine)
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
        }
    }

    private var tableCard: some View {
        VStack(spacing: 0) {
            headerRow
            Divider().overlay(PickemsColors.hairline)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(data.weeks) { weekBoard in
                        weekRow(weekBoard)
                        Divider().overlay(PickemsColors.hairline)
                    }
                }
            }
            Divider().overlay(PickemsColors.hairlineStrong)
            footerTotalRow
            Divider().overlay(PickemsColors.hairline)
            footerGamesBackRow
        }
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(PickemsColors.hairline, lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: weekColumnWidth, height: 56)
            memberColumns(height: 56) { member in
                memberHeader(member)
            }
        }
        .background(PickemsColors.cardBackground)
    }

    private func weekRow(_ board: SeasonLedgerWeekBoard) -> some View {
        let highlights = SeasonLedgerHighlight.winHighlights(weeklyWinsByMemberId: board.weeklyWinsByMemberId)
        return HStack(spacing: 0) {
            Text(SeasonLedgerWeekTitle.rowTitle(for: board.week))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PickemsColors.textPrimary)
                .frame(width: weekColumnWidth, alignment: .leading)
                .padding(.leading, 8)
                .accessibilityAddTraits(.isHeader)
            memberColumns(height: 36) { member in
                let record = board.recordsByMemberId[member.id] ?? .zero
                let highlight = highlights[member.id] ?? .none
                HStack(spacing: 0) {
                    winCell(record.wins, highlight: highlight)
                    lossCell(record.losses)
                }
                .accessibilityLabel(weekAccessibility(board: board, member: member, highlight: highlight))
            }
        }
        .padding(.vertical, 4)
    }

    private func weekAccessibility(
        board: SeasonLedgerWeekBoard,
        member: GroupMember,
        highlight: SeasonLedgerWinHighlight
    ) -> String {
        let record = board.recordsByMemberId[member.id] ?? .zero
        var phrase = "\(SeasonLedgerWeekTitle.rowTitle(for: board.week)). \(member.displayName). \(record.wins) wins, \(record.losses) losses."
        switch highlight {
        case .best: phrase += " Best week."
        case .tie: phrase += " Tied for best week."
        case .none: break
        }
        return phrase
    }

    private var footerTotalRow: some View {
        HStack(spacing: 0) {
            Text("Total")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PickemsColors.textPrimary)
                .frame(width: weekColumnWidth, alignment: .leading)
                .padding(.leading, 8)
            memberColumns(height: 40) { member in
                let season = data.seasonRecord(for: member.id)
                HStack(spacing: 0) {
                    Text("\(season.wins)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(PickemsColors.textPrimary)
                        .frame(width: memberPairWidth / 2)
                    Text("\(season.losses)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(PickemsColors.textSecondary)
                        .frame(width: memberPairWidth / 2)
                }
            }
        }
        .padding(.vertical, 6)
        .background(PickemsColors.hairlineSubtle.opacity(0.35))
        .accessibilityElement(children: .contain)
    }

    private var footerGamesBackRow: some View {
        let leaderWins = SeasonLedgerGamesBack.leaderWins(memberSeasonWins: data.seasonWinsByMemberId())
        return HStack(spacing: 0) {
            Text("Games Back")
                .font(.caption.weight(.bold))
                .foregroundStyle(PickemsColors.textSecondary)
                .frame(width: weekColumnWidth, alignment: .leading)
                .padding(.leading, 8)
            memberColumns(height: 36) { member in
                let wins = data.seasonRecord(for: member.id).wins
                let caption = SeasonLedgerGamesBack.caption(memberWins: wins, leaderWins: leaderWins)
                Text(caption)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PickemsColors.textSecondary)
                    .frame(width: memberPairWidth)
                    .accessibilityLabel(
                        caption == "—"
                            ? "\(member.displayName), even with the leader"
                            : "\(member.displayName), \(caption.replacingOccurrences(of: "−", with: "")) games back"
                    )
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func memberColumns<Content: View>(
        height: CGFloat,
        @ViewBuilder content: @escaping (GroupMember) -> Content
    ) -> some View {
        if scrollsHorizontally {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(members) { member in
                        content(member).frame(width: memberPairWidth, height: height)
                    }
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(members) { member in
                    content(member)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
        }
    }

    private func memberHeader(_ member: GroupMember) -> some View {
        let isYou = member.id == currentUserId
        return VStack(spacing: 2) {
            Text(SeasonLedgerMembers.shortName(member, currentUserId: currentUserId))
                .font(.caption.weight(.bold))
                .foregroundStyle(PickemsColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 0) {
                Text("WINS")
                Text("LOSSES")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(PickemsColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            isYou
                ? PickemsColors.defaultAccent.opacity(0.12)
                : PickemsColors.hairlineSubtle.opacity(0.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(member.displayName). Wins and losses columns.")
    }

    private func winCell(_ value: Int, highlight: SeasonLedgerWinHighlight) -> some View {
        Text("\(value)")
            .font(.subheadline.weight(.bold).monospacedDigit())
            .foregroundStyle(winForeground(highlight))
            .frame(width: memberPairWidth / 2, height: 32)
            .background(winBackground(highlight))
    }

    private func lossCell(_ value: Int) -> some View {
        Text("\(value)")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(PickemsColors.textSecondary)
            .frame(width: memberPairWidth / 2, height: 32)
    }

    private func winBackground(_ highlight: SeasonLedgerWinHighlight) -> Color {
        switch highlight {
        case .best: return PickemsColors.success
        case .tie: return PickemsColors.progressGold
        case .none: return .clear
        }
    }

    private func winForeground(_ highlight: SeasonLedgerWinHighlight) -> Color {
        switch highlight {
        case .best: return PickemsColors.onSuccess
        case .tie: return PickemsColors.onWarning
        case .none: return PickemsColors.textPrimary
        }
    }
}