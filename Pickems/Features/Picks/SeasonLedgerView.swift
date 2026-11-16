import SwiftUI

private enum SeasonLedgerScope: String, CaseIterable, Identifiable {
    case summary
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: return "Summary"
        case .detailed: return "Detailed"
        }
    }
}

struct SeasonLedgerView: View {
    @Environment(AppState.self) private var appState
    @State private var scope: SeasonLedgerScope = .summary
    @State private var loader = SeasonLedgerLoader()
    @State private var isRefreshing = false

    private var members: [GroupMember] {
        SeasonLedgerMembers.ordered(
            appState.groupService.members,
            currentUserId: appState.currentUserId
        )
    }

    var body: some View {
        Group {
            if loader.isLoading, loader.data == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading season ledger")
            } else if let data = loader.data, !data.weeks.isEmpty {
                VStack(spacing: PickemsSpacing.md) {
                    if let error = loader.errorMessage {
                        ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
                    }
                    scopePicker
                    if scope == .summary {
                        SeasonLedgerSummaryView(
                            data: data,
                            members: members,
                            currentUserId: appState.currentUserId
                        )
                    } else {
                        SeasonLedgerDetailedView(
                            data: data,
                            members: members,
                            currentUserId: appState.currentUserId
                        )
                    }
                }
                .padding(.horizontal, PickemsSpacing.md)
                .padding(.bottom, PickemsSpacing.md)
            } else if let error = loader.errorMessage {
                ContentUnavailableView(
                    "Couldn't load ledger",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ContentUnavailableView(
                    "No Ledger Yet",
                    systemImage: "tablecells",
                    description: Text("Locked and scored weeks appear here after Pickems lock.")
                )
            }
        }
        .navigationTitle("Season Ledger")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HelpInfoButton(topic: PickemsHelp.seasonHistory, size: .body)
            }
        }
        .task(id: appState.groupService.selectedGroup?.id) {
            await loader.loadIfNeeded(appState: appState)
        }
        .pickemsRefreshable(isRefreshing: $isRefreshing) {
            await loader.reload(appState: appState)
        }
    }

    private var scopePicker: some View {
        Picker("Ledger view", selection: $scope) {
            ForEach(SeasonLedgerScope.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Season ledger view")
    }
}