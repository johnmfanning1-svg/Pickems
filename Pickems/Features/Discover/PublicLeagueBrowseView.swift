import SwiftUI

/// Public-league list pushed from the search/join sheet. Joining calls the same
/// invite-code path as typing a code.
struct PublicLeagueBrowseView: View {
    /// Returns a message to show, or nil after a successful open/join.
    var performJoin: (PublicLeagueListing) async -> String?

    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var service = DiscoverService()
    @State private var joiningId: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text(PublicLeagueBrowse.intro)
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .listRowBackground(PickemsColors.cardBackground)
            }

            if service.isLoading && service.leagues.isEmpty {
                ProgressView()
                    .listRowBackground(PickemsColors.cardBackground)
                    .accessibilityLabel("Loading public leagues")
            } else if service.leagues.isEmpty {
                Text(service.errorMessage ?? PublicLeagueBrowse.emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(service.errorMessage == nil ? PickemsColors.textSecondary : theme.accent)
                    .listRowBackground(PickemsColors.cardBackground)
            } else {
                ForEach(service.leagues) { league in
                    leagueRow(league)
                }
            }

            if let loadError = service.errorMessage, !service.leagues.isEmpty {
                Section {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(theme.accent)
                        .listRowBackground(PickemsColors.cardBackground)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(theme.accent)
                        .listRowBackground(PickemsColors.cardBackground)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .navigationTitle(PublicLeagueBrowse.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.refresh() }
        .refreshable { await service.refresh() }
    }

    private func leagueRow(_ league: PublicLeagueListing) -> some View {
        let alreadyMember = memberGroupIds.contains(league.groupId)
        let joining = joiningId == league.groupId
        return Button {
            join(league)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(league.name)
                        .font(.headline)
                        .foregroundStyle(PickemsColors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(PublicLeagueBrowse.memberCountLabel(league.memberCount))
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                Spacer(minLength: 8)
                if joining {
                    ProgressView()
                        .tint(theme.accent)
                } else {
                    Text(PublicLeagueBrowse.actionTitle(alreadyMember: alreadyMember))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(joiningId != nil)
        .listRowBackground(PickemsColors.cardBackground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            joining
                ? "\(alreadyMember ? "Opening" : "Joining") \(league.name)"
                : PublicLeagueBrowse.rowLabel(
                    name: league.name,
                    memberCount: league.memberCount,
                    alreadyMember: alreadyMember
                )
        )
        .accessibilityHint(PublicLeagueBrowse.actionHint(alreadyMember: alreadyMember))
        .accessibilityAddTraits(.isButton)
    }

    private var memberGroupIds: Set<String> {
        Set(appState.groupService.groups.map(\.id))
    }

    private func join(_ league: PublicLeagueListing) {
        guard joiningId == nil else { return }
        joiningId = league.groupId
        errorMessage = nil
        Task {
            defer { joiningId = nil }
            errorMessage = await performJoin(league)
        }
    }
}
