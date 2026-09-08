import SwiftUI

/// Designed at 1200×630 (Open Graph / iMessage). Scale down for in-app preview.
struct ResultsShareCard: View {
    let result: ShareableResult
    var palette: ThemePalette = .pickemsDefault

    var body: some View {
        ZStack {
            PickemsColors.background
            LinearGradient(
                colors: [
                    palette.atmospheric.opacity(0.42),
                    palette.accent.opacity(0.16),
                    Color.clear,
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 16)
                heroRow
                Text(result.displayName)
                    .font(PickemsTypography.display(34, weight: .semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 8)
                Text(result.detailLine)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(PickemsColors.textPrimary.opacity(0.92))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
                Text(result.bragLine)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
                    .padding(.top, 18)
                Spacer(minLength: 12)
                footer
            }
            .padding(52)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(kicker). \(result.heroText). \(result.displayName). \(result.detailLine). \(result.bragLine)"
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("PICKEMS")
                .font(.system(size: 22, weight: .black))
                .tracking(2.4)
                .foregroundStyle(PickemsColors.textPrimary)
            Spacer(minLength: 16)
            Text(result.leagueName.uppercased())
                .font(.system(size: 20, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(PickemsColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kicker)
                    .font(.system(size: 20, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(palette.accent)
                Text(result.heroText)
                    .font(PickemsTypography.display(148))
                    .monospacedDigit()
                    .foregroundStyle(PickemsColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            }
            Spacer(minLength: 8)
            rankBadge
        }
    }

    private var rankBadge: some View {
        Text(badgeText)
            .font(PickemsTypography.display(28, weight: .bold))
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(palette.accent, in: Capsule())
    }

    private var badgeText: String {
        if result.type == .seasonEnd {
            return "of \(result.totalPlayers)"
        }
        return result.rankText
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Get Pickems on the App Store")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 12)
            Text("\(AppConfig.cfbHashtag)  \(AppConfig.appHashtag)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PickemsColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var kicker: String {
        if let week = result.week {
            return "WEEK \(week)"
        }
        return "\(result.season) SEASON"
    }
}

struct ScaledShareCardPreview: View {
    let result: ShareableResult
    var palette: ThemePalette = .pickemsDefault

    var body: some View {
        GeometryReader { geo in
            let scale = max(geo.size.width / 1200, 0.01)
            ResultsShareCard(result: result, palette: palette)
                .frame(width: 1200, height: 630)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: 630 * scale, alignment: .topLeading)
        }
        .aspectRatio(1200 / 630, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

#if DEBUG
struct ResultsShareCard_Previews: PreviewProvider {
    static var previews: some View {
        ScaledShareCardPreview(result: ShareableResult(weekly: DemoData.weeklyResult))
            .padding()
            .background(PickemsColors.background)
    }
}
#endif
