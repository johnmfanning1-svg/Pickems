import SwiftUI
import FirebaseFirestore

struct PublicLeagueListing: Codable, Identifiable, Equatable {
    var id: String { groupId }
    var groupId: String
    var name: String
    var inviteCode: String
    var memberCount: Int
}

@MainActor
@Observable
final class DiscoverService {
    var leagues: [PublicLeagueListing] = []
    var isLoading = false
    var errorMessage: String?

    private let db = Firestore.firestore()

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await db.collection("publicLeagues")
                .order(by: "memberCount", descending: true)
                .limit(to: 40)
                .getDocuments()
            leagues = snap.documents.compactMap { try? $0.data(as: PublicLeagueListing.self) }
        } catch {
            UserFacingError.apply(error, to: &errorMessage)
        }
    }
}

struct DiscoverLeaguesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var service = DiscoverService()
    @State private var joiningId: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Public leagues anyone can join. Private invite-only groups stay hidden.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .listRowBackground(PickemsColors.cardBackground)
            }

            if service.isLoading {
                ProgressView()
                    .listRowBackground(PickemsColors.cardBackground)
            } else if service.leagues.isEmpty {
                Text("No public leagues yet. Commissioners can enable Discover in settings.")
                    .foregroundStyle(PickemsColors.textSecondary)
                    .listRowBackground(PickemsColors.cardBackground)
            } else {
                ForEach(service.leagues) { league in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(league.name)
                                .font(.headline)
                            Text("\(league.memberCount) members")
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                        }
                        Spacer()
                        Button {
                            join(league)
                        } label: {
                            if joiningId == league.groupId {
                                ProgressView()
                            } else {
                                Text("Join")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .foregroundStyle(theme.accent)
                        .disabled(joiningId != nil)
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(theme.accent)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .navigationTitle("Discover")
        .task { await service.refresh() }
        .refreshable { await service.refresh() }
    }

    private func join(_ league: PublicLeagueListing) {
        joiningId = league.groupId
        errorMessage = nil
        Task {
            defer { joiningId = nil }
            do {
                try await appState.joinGroup(inviteCode: league.inviteCode, markOnboarding: true)
                PickemsHaptics.success()
                appState.selectedTab = .groups
            } catch {
                errorMessage = UserFacingError.message(for: error, context: .joinGroup)
                    ?? "Couldn't join that league. Try again."
            }
        }
    }
}
