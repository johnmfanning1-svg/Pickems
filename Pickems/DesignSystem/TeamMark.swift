import SwiftUI

/// Compact team logo with an optional Top 25 `#N` overlay inside the logo frame.
struct TeamMark: View {
    let logoURL: String?
    let abbreviation: String
    var rank: Int? = nil
    var size: CGFloat = 32
    /// When true and logo is missing, show abbreviation as the mark (live scoreboard style).
    var showsAbbreviationFallback: Bool = true

    private var displayRank: Int? {
        guard let rank, (1...25).contains(rank) else { return nil }
        return rank
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            logoContent
                .frame(width: size, height: size)

            if let displayRank {
                Text("#\(displayRank)")
                    .font(.system(size: max(8, size * 0.28), weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .offset(x: -2, y: -2)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
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
