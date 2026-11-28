import SwiftUI

struct SeasonLedgerShareCard: View {
    let model: SeasonLedgerShareModel

    private var weekWidth: CGFloat { model.weekColumnWidth }
    private var memberWidth: CGFloat { model.memberColumnWidth }

    private var tableWidth: CGFloat {
        weekWidth + CGFloat(model.columns.count) * memberWidth
    }

    var body: some View {
        ShareCardChrome(
            leagueName: model.leagueName,
            periodLabel: "Season",
            contextTitle: "Season Ledger",
            leagueShareURL: AppConfig.leagueShareURL(groupId: model.groupId)
        ) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                ForEach(Array(model.weeks.enumerated()), id: \.offset) { _, week in
                    weekRow(week)
                }
                footerRow(title: "Total", values: model.seasonTotals, bold: true)
                footerRow(title: "Games Back", captions: model.gamesBack)
                if model.omittedMemberCount > 0 {
                    Text("+\(model.omittedMemberCount) more")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                        .padding(.top, 12)
                }
            }
            .frame(width: tableWidth, alignment: .leading)
            .background(PickemsColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(PickemsColors.hairline, lineWidth: 1)
            )
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: weekWidth, alignment: .leading)
            ForEach(Array(model.columns.enumerated()), id: \.offset) { _, column in
                Text(column.shortName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(column.isViewer ? PickemsColors.accent : PickemsColors.textPrimary)
                    .frame(width: memberWidth)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, 10)
        .background(PickemsColors.hairlineSubtle.opacity(0.35))
    }

    private func weekRow(_ week: ShareLedgerWeekRow) -> some View {
        HStack(spacing: 0) {
            Text(week.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PickemsColors.textPrimary)
                .frame(width: weekWidth, alignment: .leading)
                .padding(.leading, 8)

            ForEach(Array(week.records.enumerated()), id: \.offset) { index, record in
                wlPair(record, highlight: false)
                    .frame(width: memberWidth)
                    .background(index < model.columns.count && model.columns[index].isViewer ? PickemsColors.hairlineSubtle.opacity(0.2) : Color.clear)
            }
        }
        .padding(.vertical, 6)
    }

    private func footerRow(title: String, values: [ShareLedgerWLPair], bold: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 17, weight: bold ? .bold : .semibold))
                .foregroundStyle(PickemsColors.textPrimary)
                .frame(width: weekWidth, alignment: .leading)
                .padding(.leading, 8)

            ForEach(Array(values.enumerated()), id: \.offset) { _, record in
                wlPair(record, highlight: false, bold: bold)
                    .frame(width: memberWidth)
            }
        }
        .padding(.vertical, 8)
        .background(PickemsColors.hairlineSubtle.opacity(0.25))
    }

    private func footerRow(title: String, captions: [String]) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PickemsColors.textSecondary)
                .frame(width: weekWidth, alignment: .leading)
                .padding(.leading, 8)

            ForEach(Array(captions.enumerated()), id: \.offset) { _, caption in
                Text(caption)
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(PickemsColors.textSecondary)
                    .frame(width: memberWidth)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 6)
    }

    private func wlPair(_ record: ShareLedgerWLPair, highlight: Bool, bold: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text("\(record.wins)")
                .font(.system(size: bold ? 20 : 18, weight: bold ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(highlight ? PickemsColors.success : PickemsColors.textPrimary)
                .frame(maxWidth: .infinity)
            Text("\(record.losses)")
                .font(.system(size: bold ? 18 : 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(PickemsColors.textSecondary)
                .frame(maxWidth: .infinity)
        }
    }
}