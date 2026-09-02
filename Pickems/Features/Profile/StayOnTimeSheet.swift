import SwiftUI

/// Shown once after account creation / first session while iOS permission is still undetermined.
struct StayOnTimeSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)

                Text("Stay on time")
                    .font(.title2.bold())
                    .foregroundStyle(PickemsColors.textPrimary)

                Text("Allow notifications so Pickems can remind you before deadlines and when games finish. You can choose which alerts you get later in Profile.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                PrimaryButton(title: "Allow notifications") {
                    Task {
                        await appState.notificationService.requestPermission()
                        if let uid = appState.currentUserId {
                            appState.authService.markNotificationOnboardingDismissed(for: uid)
                            await appState.notificationService.saveToken(for: uid)
                        }
                        dismiss()
                    }
                }

                Button("Not now") {
                    if let uid = appState.currentUserId {
                        appState.authService.markNotificationOnboardingDismissed(for: uid)
                    }
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
                .frame(maxWidth: .infinity)
            }
            .padding()
            .pickemsScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if let uid = appState.currentUserId {
                            appState.authService.markNotificationOnboardingDismissed(for: uid)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
