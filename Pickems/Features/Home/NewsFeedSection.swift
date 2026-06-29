import SwiftUI

struct NewsFeedSection: View {
    let items: [ESPNNewsItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(
                title: "CFB News",
                subtitle: "Headlines from ESPN"
            )

            if items.isEmpty {
                Text("No headlines right now.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { item in
                            NewsCard(item: item)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct NewsCard: View {
    let item: ESPNNewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageURL = item.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 220, height: 120)
                .clipped()
            }
            Text(item.headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PickemsColors.textPrimary)
                .lineLimit(3)
            Text(item.publishedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(PickemsColors.textSecondary)
        }
        .frame(width: 220)
        .padding(10)
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if let link = item.link {
                UIApplication.shared.open(link)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.headline)
    }
}

struct WeekRecapCard: View {
    let recapText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Week Recap", systemImage: "text.quote")
                .font(.headline)
                .foregroundStyle(PickemsColors.accent)

            Text(recapText)
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ShareLink(item: recapText) {
                Label("Share Recap", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.accent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(PickemsColors.accent.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}
