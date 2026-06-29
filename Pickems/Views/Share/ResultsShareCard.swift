import SwiftUI

struct ResultsShareCard: View {
    let result: ShareableResult

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.08, blue: 0.18), Color(red: 0.12, green: 0.18, blue: 0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Image(systemName: "football.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text("PICKEMS")
                        .font(.headline.weight(.black))
                        .tracking(2)
                    Spacer()
                    Text(result.leagueName.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(result.headline)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(result.statsLine)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }

                Text(result.bragLine)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                HStack {
                    Text(result.promoURL)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.cyan)
                    Spacer()
                    Text("\(AppConfig.cfbHashtag) \(AppConfig.appHashtag)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(48)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

#if DEBUG
struct ResultsShareCard_Previews: PreviewProvider {
    static var previews: some View {
        ResultsShareCard(result: ShareableResult(weekly: DemoData.weeklyResult))
            .frame(width: 600, height: 315)
            .padding()
    }
}
#endif
