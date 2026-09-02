import SwiftUI
import UserNotifications

/// Chooses which FCM alerts the signed-in user receives. Presented from Profile
/// so the tab stays a single row instead of a stack of toggles.
struct NotificationSettingsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    systemPermissionControls
                        .listRowBackground(PickemsColors.cardBackground)
                } header: {
                    Text("iOS permission")
                } footer: {
                    Text(systemPermissionFooter)
                }

                ForEach(NotificationPrefCategory.Group.allCases) { group in
                    Section {
                        ForEach(NotificationPrefCategory.categories(in: group)) { category in
                            Toggle(isOn: binding(for: category)) {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(category.title)
                                            .foregroundStyle(PickemsColors.textPrimary)
                                        Text(category.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(PickemsColors.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                } icon: {
                                    Image(systemName: category.systemImage)
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            .listRowBackground(PickemsColors.cardBackground)
                            .accessibilityHint(category.subtitle)
                        }
                    } header: {
                        Text(group.title)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.warning)
                            .listRowBackground(PickemsColors.cardBackground)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await appState.notificationService.syncWithSystem()
                if let uid = appState.currentUserId {
                    await appState.notificationService.saveToken(for: uid)
                }
            }
        }
    }

    @ViewBuilder
    private var systemPermissionControls: some View {
        switch appState.notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            HStack {
                Label("Enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(PickemsColors.success)
                Spacer()
                Button("Open Settings") {
                    appState.notificationService.openSystemSettings()
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
            }
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label("Off — blocked in iOS Settings", systemImage: "bell.slash.fill")
                    .foregroundStyle(PickemsColors.warning)
                Button {
                    appState.notificationService.openSystemSettings()
                } label: {
                    Text("Enable in Settings")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }
        case .notDetermined:
            Button {
                Task {
                    await appState.notificationService.requestPermission()
                    if let uid = appState.currentUserId {
                        await appState.notificationService.saveToken(for: uid)
                    }
                }
            } label: {
                Text("Allow notifications")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
        @unknown default:
            Button("Refresh status") {
                Task { await appState.notificationService.refreshAuthorizationStatus() }
            }
            .buttonStyle(.borderless)
        }
    }

    private var systemPermissionFooter: String {
        switch appState.notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "To block every Pickems alert, use Open Settings → Notifications."
        case .denied:
            return "iOS blocked alerts for Pickems. Enable them in Settings, then choose types here."
        default:
            return "You’ll get an iOS permission prompt when you tap Allow notifications."
        }
    }

    private func binding(for category: NotificationPrefCategory) -> Binding<Bool> {
        Binding(
            get: { appState.authService.currentUser?.wants(category) ?? true },
            set: { enabled in
                Task { await setPref(category, enabled: enabled) }
            }
        )
    }

    private func setPref(_ category: NotificationPrefCategory, enabled: Bool) async {
        errorMessage = nil
        if enabled {
            await appState.notificationService.refreshAuthorizationStatus()
            switch appState.notificationService.authorizationStatus {
            case .notDetermined:
                await appState.notificationService.requestPermission()
            case .denied:
                appState.notificationService.openSystemSettings()
            default:
                if let uid = appState.currentUserId {
                    await appState.notificationService.saveToken(for: uid)
                }
            }
        }
        do {
            try await appState.authService.updateNotificationPref(category, enabled: enabled)
        } catch {
            errorMessage = UserFacingError.message(for: error, context: .write)
                ?? error.localizedDescription
        }
    }
}
