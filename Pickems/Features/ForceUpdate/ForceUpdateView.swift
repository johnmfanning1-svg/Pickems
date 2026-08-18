import SwiftUI

/// Full-screen block when `appConfig/live.minimumBuild` is above this binary.
/// No dismiss — the only way out is the App Store.
struct ForceUpdateView: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 48))
                .foregroundStyle(theme.accent)
            Text("Update required")
                .font(.title2.weight(.semibold))
                .foregroundStyle(PickemsColors.textPrimary)
            Text("This version of Pickems is no longer supported. Update to keep making Selections and Pickems with your league.")
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            PrimaryButton(title: "Update on the App Store") {
                if let url = URL(string: AppConfig.appStoreURL) {
                    openURL(url)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PickemsAtmosphericBackground(palette: theme))
        .interactiveDismissDisabled()
    }
}
