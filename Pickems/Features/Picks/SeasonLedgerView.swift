import SwiftUI

enum SeasonLedgerScope: String, CaseIterable, Identifiable {
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
    @State private var showExpandedLedger = false

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
                    if loader.showsRefreshFailureBanner {
                        SeasonLedgerRefreshFailureBanner(isLoading: loader.isLoading) {
                            Task { await loader.reload(appState: appState) }
                        }
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
            } else if loader.showsFullLoadError, let error = loader.errorMessage {
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
                HStack(spacing: 4) {
                    if loader.data != nil, !(loader.data?.weeks.isEmpty ?? true),
                       let data = loader.data,
                       let leagueName = appState.groupService.selectedGroup?.name {
                        ShareScreenButton(
                            accessibilityLabel: "Share season ledger",
                            buildContent: {
                                ScreenShareContent.makeSeasonLedger(
                                    leagueName: leagueName,
                                    data: data,
                                    members: members,
                                    currentUserId: appState.currentUserId
                                )
                            }
                        )
                        Button {
                            showExpandedLedger = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityLabel("Expand season ledger to full screen")
                    }
                    HelpInfoButton(topic: PickemsHelp.seasonLedger, size: .body)
                }
            }
        }
        .fullScreenCover(isPresented: $showExpandedLedger) {
            if let data = loader.data {
                SeasonLedgerExpandedView(
                    scope: $scope,
                    data: data,
                    members: members,
                    currentUserId: appState.currentUserId
                )
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

/// Landscape fullscreen ledger. Portrait lock is restored on dismiss.
struct SeasonLedgerExpandedView: View {
    @Binding var scope: SeasonLedgerScope
    let data: SeasonLedgerSeasonData
    let members: [GroupMember]
    let currentUserId: String?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    var body: some View {
        NavigationStack {
            VStack(spacing: PickemsSpacing.md) {
                Picker("Ledger view", selection: $scope) {
                    ForEach(SeasonLedgerScope.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Season ledger view")

                if scope == .summary {
                    SeasonLedgerSummaryView(
                        data: data,
                        members: members,
                        currentUserId: currentUserId
                    )
                } else {
                    SeasonLedgerDetailedView(
                        data: data,
                        members: members,
                        currentUserId: currentUserId
                    )
                }
            }
            .padding(.horizontal, PickemsSpacing.md)
            .padding(.bottom, PickemsSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .pickemsScreenBackground()
            .navigationTitle("Season Ledger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Exit full screen")
                }
                ToolbarItem(placement: .primaryAction) {
                    if let leagueName = appState.groupService.selectedGroup?.name, !data.weeks.isEmpty {
                        ShareScreenButton(
                            accessibilityLabel: "Share season ledger",
                            buildContent: {
                                ScreenShareContent.makeSeasonLedger(
                                    leagueName: leagueName,
                                    data: data,
                                    members: members,
                                    currentUserId: currentUserId
                                )
                            }
                        )
                    }
                }
            }
        }
        .statusBarHidden(true)
        .onAppear { InterfaceOrientationLock.set(.landscape) }
        .onDisappear { InterfaceOrientationLock.set(.portrait) }
    }
}

/// Non-blocking refresh failure while stale ledger data remains visible.
private struct SeasonLedgerRefreshFailureBanner: View {
    let isLoading: Bool
    let onRetry: () -> Void
    @Environment(\.themePalette) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)

            Text(SeasonLedgerRefreshPresentation.staleRefreshBannerMessage)
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(SeasonLedgerRefreshPresentation.staleRefreshBannerMessage)

            Spacer(minLength: 0)

            Button("Retry", action: onRetry)
                .font(.subheadline.weight(.semibold))
                .disabled(isLoading)
                .accessibilityLabel("Retry loading season ledger")
        }
        .padding()
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.15), lineWidth: 1)
        )
    }
}
