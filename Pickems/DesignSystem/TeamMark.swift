import SwiftUI

/// Compact team logo with an optional ESPN-style Top 25 rank to the left of the mark.
///
/// Ranked teams show a small number beside the logo (`14` next to USC), never as a
/// pill over the artwork. Unranked teams keep the original square mark.
struct TeamMark: View {
    let logoURL: String?
    let abbreviation: String
    var rank: Int? = nil
    var size: CGFloat = 32
    /// When true and logo is missing, show abbreviation as the mark (live scoreboard style).
    var showsAbbreviationFallback: Bool = true

    private var displayRank: Int? {
        TeamDisplay.top25Rank(rank)
    }

    /// Two-digit gutter so `5` and `25` both sit against the logo, ESPN-style.
    private var rankColumnWidth: CGFloat {
        max(12, (size * 0.44).rounded())
    }

    private var rankFontSize: CGFloat {
        max(9, (size * 0.34).rounded())
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            if let rankText = TeamDisplay.logoRankText(rank) {
                Text(rankText)
                    .font(.system(size: rankFontSize, weight: .bold))
                    .foregroundStyle(PickemsColors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: rankColumnWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }

            logoContent
                .frame(width: size, height: size)
        }
        .frame(height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let displayRank {
            return "Ranked \(displayRank) \(abbreviation)"
        }
        return abbreviation
    }

    @ViewBuilder
    private var logoContent: some View {
        if let logoURL, let url = URL(string: logoURL) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                fallbackMark
            }
        } else if showsAbbreviationFallback {
            fallbackMark
        } else {
            Image(systemName: "football.fill")
                .resizable()
                .scaledToFit()
                .padding(size * 0.15)
                .foregroundStyle(PickemsColors.textSecondary)
        }
    }

    private var fallbackMark: some View {
        Text(abbreviation)
            .font(.system(size: size * 0.32, weight: .bold))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(PickemsColors.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
