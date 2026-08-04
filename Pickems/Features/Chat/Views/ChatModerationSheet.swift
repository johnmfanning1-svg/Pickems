import SwiftUI

/// The Guideline 1.2 control surface for a single message: report it, block its
/// author, or soft-delete your own. Presented from `ChatMessageRow`'s context menu.
struct ChatModerationSheet: View {
    let message: ChatMessage

    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ChatReportReason = .harassment
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var didReport = false

    private var isOwnMessage: Bool {
        message.userId == appState.currentUserId
    }

    var body: some View {
        NavigationStack {
            Form {
                messageSection

                if isOwnMessage {
                    deleteSection
                } else {
                    reportSection
                    blockSection
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(PickemsColors.warning)
                    }
                }

                policySection
            }
            .navigationTitle(isOwnMessage ? "Your Message" : "Report or Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var messageSection: some View {
        Section("Message") {
            VStack(alignment: .leading, spacing: 6) {
                Text(message.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                Task { await deleteOwn() }
            } label: {
                Label("Delete Message", systemImage: "trash")
            }
            .disabled(isWorking || message.isDeleted)
        } footer: {
            Text("Deleted messages are replaced with a placeholder so the rest of the thread still reads in order.")
        }
    }

    private var reportSection: some View {
        Section("Report") {
            Picker("Reason", selection: $reason) {
                ForEach(ChatReportReason.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Button {
                Task { await report() }
            } label: {
                Label(didReport ? "Reported" : "Report Message", systemImage: "flag")
            }
            .disabled(isWorking || didReport)
        }
    }

    private var blockSection: some View {
        Section {
            let isBlocked = appState.chatService.isBlocked(message.userId)
            Button(role: isBlocked ? nil : ButtonRole.destructive) {
                toggleBlock(isBlocked: isBlocked)
            } label: {
                Label(
                    isBlocked ? "Unblock \(message.displayName)" : "Block \(message.displayName)",
                    systemImage: isBlocked ? "person.crop.circle.badge.checkmark" : "hand.raised"
                )
            }
            .disabled(isWorking)
        } footer: {
            Text("Blocking hides every message from this person on this device, right away.")
        }
    }

    private var policySection: some View {
        Section {
            if let url = AppConfig.termsOfServiceURL {
                Link("Terms of Service", destination: url)
                    .font(.footnote)
            }
        } footer: {
            Text("Reported messages are reviewed and accounts that break the rules can be removed. A message hidden by \(ChatService.autoHideReportThreshold) reports disappears for everyone until it is reviewed.")
        }
    }

    // MARK: - Actions

    private func report() async {
        guard let reporterId = appState.currentUserId else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await appState.chatService.report(message, reason: reason, reporterId: reporterId)
            didReport = true
            PickemsHaptics.success()
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(for: error, context: .write)
                ?? "Couldn't send that report. Try again in a moment."
        }
    }

    private func deleteOwn() async {
        guard let userId = appState.currentUserId else { return }
        isWorking = true
        defer { isWorking = false }
        await appState.chatService.deleteOwnMessage(message, userId: userId)
        if let serviceError = appState.chatService.errorMessage {
            errorMessage = serviceError
        } else {
            PickemsHaptics.success()
            dismiss()
        }
    }

    private func toggleBlock(isBlocked: Bool) {
        guard let ownerId = appState.currentUserId else { return }
        if isBlocked {
            appState.chatService.unblock(userId: message.userId, ownerId: ownerId)
        } else {
            appState.chatService.block(userId: message.userId, ownerId: ownerId)
            PickemsHaptics.warning()
        }
        dismiss()
    }
}
