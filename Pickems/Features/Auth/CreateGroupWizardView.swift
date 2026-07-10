import SwiftUI

struct CreateGroupWizardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    @State private var step = 0
    @State private var groupName = ""
    @State private var rules = GroupRules.default
    @State private var isWorking = false
    @State private var errorMessage: String?

    var onComplete: () -> Void = {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 3)
                    .tint(theme.accent)
                    .padding()

                TabView(selection: $step) {
                    nameStep.tag(0)
                    rulesStep.tag(1)
                    reviewStep.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: step)

                HStack {
                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                    Spacer()
                    if step < 2 {
                        PrimaryButton(title: "Next") { step += 1 }
                            .frame(width: 120)
                            .disabled(step == 0 && groupName.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        PrimaryButton(title: "Create League", isLoading: isWorking) {
                            create()
                        }
                        .frame(width: 160)
                    }
                }
                .padding()
            }
            .pickemsScreenBackground()
            .navigationTitle("Create League")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name your league")
                .font(.title2.bold())
                .foregroundStyle(PickemsColors.textPrimary)
            Text("You'll be the commissioner and can invite friends with a code.")
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)

            TextField("PPP Pickems", text: $groupName)
                .textFieldStyle(.pickems)

            HelpInfoButton(topic: PickemsHelp.createGroup)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var rulesStep: some View {
        Form {
            Section("Selection") {
                Picker("Mode", selection: $rules.selectionMode) {
                    ForEach(SelectionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Stepper("Games per week: \(rules.slateSize)", value: $rules.slateSize, in: 1...20)
                if rules.selectionMode == .member {
                    Stepper("Per member: \(rules.selectionsPerMember)", value: $rules.selectionsPerMember, in: 1...10)
                }
            }
            Section("Deadlines") {
                Picker("Pick deadline", selection: $rules.pickDeadline) {
                    ForEach(DeadlinePolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                Picker("Tie breaker", selection: $rules.tieBreaker) {
                    ForEach(TieBreakerPolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review")
                .font(.title2.bold())
                .foregroundStyle(PickemsColors.textPrimary)

            PickemsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(groupName.isEmpty ? "My Pickems" : groupName)
                        .font(.headline)
                    Text(rules.selectionMode.displayName)
                    Text("\(rules.slateSize) games · \(rules.pickDeadline.displayName)")
                    Text("Tie-breaker: \(rules.tieBreaker.displayName)")
                }
                .foregroundStyle(PickemsColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(theme.accent)
            }

            Spacer()
        }
        .padding()
    }

    private func create() {
        Task {
            isWorking = true
            errorMessage = nil
            defer { isWorking = false }

            guard let user = appState.authService.currentUser else {
                errorMessage = "No signed-in user. Sign in to continue."
                return
            }
            do {
                let group = try await appState.groupService.createGroup(
                    name: groupName.isEmpty ? "My Pickems" : groupName,
                    commissionerId: user.id,
                    displayName: user.displayName
                )
                try await appState.groupService.updateRules(groupId: group.id, rules: rules)
                appState.groupService.loadGroups(for: user.id)
                appState.finishOnboarding(for: user.id)
                PickemsHaptics.success()
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
