import Combine
import SwiftUI

/// Attach to your app root to enable sharing (X, text, invites).
struct SharingBootstrap<Content: View>: View {
    @StateObject private var xAuthService = XAuthService()
    @StateObject private var shareCoordinator = ResultsShareCoordinator()

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environmentObject(xAuthService)
            .environmentObject(shareCoordinator)
            .sheet(isPresented: weeklySheetBinding) {
                if let result = shareCoordinator.pendingWeeklyShare {
                    ShareResultsSheet(source: .weekly(result))
                        .environmentObject(xAuthService)
                }
            }
            .sheet(isPresented: seasonSheetBinding) {
                if let standing = shareCoordinator.pendingSeasonShare {
                    ShareResultsSheet(source: .season(standing))
                        .environmentObject(xAuthService)
                }
            }
    }

    private var weeklySheetBinding: Binding<Bool> {
        Binding(
            get: { shareCoordinator.pendingWeeklyShare != nil },
            set: { isPresented in
                if !isPresented {
                    shareCoordinator.clearWeekly()
                }
            }
        )
    }

    private var seasonSheetBinding: Binding<Bool> {
        Binding(
            get: { shareCoordinator.pendingSeasonShare != nil },
            set: { isPresented in
                if !isPresented {
                    shareCoordinator.clearSeason()
                }
            }
        )
    }
}

extension View {
    /// Call on your root view if you are not using `SharingBootstrap` directly.
    func withSharingSupport(
        xAuthService: XAuthService,
        shareCoordinator: ResultsShareCoordinator
    ) -> some View {
        environmentObject(xAuthService)
            .environmentObject(shareCoordinator)
    }
}
