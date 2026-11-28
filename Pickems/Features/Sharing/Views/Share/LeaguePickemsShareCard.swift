import SwiftUI

struct LeaguePickemsShareCard: View {
    let model: PickemsChartShareModel

    private let gameWidth: CGFloat = 200
    private let columnWidth: CGFloat = 72

    var body: some View {
        ShareCardChrome(
            leagueName: model.leagueName,
            periodLabel: model.periodLabel,
            contextTitle: "League Pickems",
            leagueShareURL: AppConfig.leagueShareURL(groupId: model.groupId)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                colorKey
                chartTable
                footnotes
            }
        }
    }

    private var colorKey: some View {
        HStack(spacing: 8) {
            keyChip("Trailing", fill: PickemsColors.warning, ink: PickemsColors.onWarning)
            keyChip("Covering", fill: PickemsColors.covering, ink: PickemsColors.onCovering)
            keyChip("Won", fill: PickemsColors.success, ink: PickemsColors.onSuccess)
            keyChip("Lost", fill: PickemsColors.lost, ink: PickemsColors.onLost)
            keyChip("Push", fill: PickemsColors.push, ink: PickemsColors.onPush)
        }
    }

    private func keyChip(_ title: String, fill: Color, ink: Color) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(fill)
            .clipShape(Capsule())
    }

    private var chartTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Game")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .frame(width: gameWidth, alignment: .leading)
                    .padding(.leading, 8)

                ForEach(Array(model.columns.enumerated()), id: \.offset) { _, column in
                    Text(column.shortName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(column.isViewer ? PickemsColors.accent : PickemsColors.textPrimary)
                        .frame(width: columnWidth)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.vertical, 10)
            .background(PickemsColors.cardBackground)

            ForEach(Array(model.games.enumerated()), id: \.offset) { _, game in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.matchup)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(PickemsColors.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        if let score = game.scoreLine {
                            Text(score)
                                .font(.system(size: 15, weight: .medium).monospacedDigit())
                                .foregroundStyle(PickemsColors.textSecondary)
                        }
                    }
                    .frame(width: gameWidth, alignment: .leading)
                    .padding(.leading, 8)
                    .padding(.vertical, 8)

                    ForEach(Array(game.cells.enumerated()), id: \.offset) { index, cell in
                        cellView(cell)
                            .frame(width: columnWidth, height: 52)
                            .background(index < model.columns.count && model.columns[index].isViewer ? PickemsColors.hairlineSubtle.opacity(0.15) : Color.clear)
                    }
                }
                .background(PickemsColors.cardBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PickemsColors.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func cellView(_ cell: ShareChartCell) -> some View {
        switch cell.kind {
        case .locked:
            Image(systemName: "lock.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PickemsColors.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PickemsColors.cardBackground)
        case .empty:
            Text("—")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PickemsColors.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PickemsColors.cardBackground)
        case .pick(let abbrev, let status):
            Text(abbrev)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(shareForeground(status))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shareFill(status))
        }
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.omittedMemberCount > 0 {
                Text("+\(model.omittedMemberCount) more members")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
            }
            if model.omittedGameCount > 0 {
                Text("+\(model.omittedGameCount) more games")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
            }
        }
    }

    private func shareFill(_ status: PickBoardStatus) -> Color {
        SeasonLedgerPickStyle.fill(for: status)
    }

    private func shareForeground(_ status: PickBoardStatus) -> Color {
        SeasonLedgerPickStyle.foreground(for: status)
    }
}