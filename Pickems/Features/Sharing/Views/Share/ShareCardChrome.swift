import SwiftUI

struct ShareCardChrome<Body: View>: View {
    let leagueName: String
    let periodLabel: String
    let contextTitle: String
  /// Optional subtitle under the context line (e.g. standings scope hint).
    var detailSubtitle: String? = nil
    @ViewBuilder let bodyContent: () -> Body

    var body: some View {
        ZStack {
            PickemsColors.background
            VStack(alignment: .leading, spacing: 0) {
                header
                Text(contextTitle)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(PickemsColors.textPrimary)
                    .padding(.top, 20)
                if let detailSubtitle {
                    Text(detailSubtitle)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(PickemsColors.textSecondary)
                        .padding(.top, 4)
                }
                bodyContent()
                    .padding(.top, 24)
                Spacer(minLength: 16)
                footer
            }
            .padding(48)
            .frame(width: ShareCardLayout.renderWidth, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("PICKEMS")
                    .font(.system(size: 22, weight: .black))
                    .tracking(2.4)
                    .foregroundStyle(PickemsColors.textPrimary)
                Spacer(minLength: 12)
                Text("CFB Pickems")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
            }
            Text(leagueName.uppercased())
                .font(.system(size: 24, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(PickemsColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(periodLabel)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PickemsColors.textPrimary.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Get Pickems on the App Store")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PickemsColors.accent)
            Text(AppConfig.appStoreURL)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(PickemsColors.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShareStaticAvatar: View {
    let initials: String
    let colorHex: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(PickemsColors.color(from: colorHex))
            Text(initials)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}