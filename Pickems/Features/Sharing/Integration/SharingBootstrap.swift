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
            // Use `sheet(item:)` — `sheet(isPresented:)` with `if let` content can present an
            // empty hierarchy and crash SwiftUI on TestFlight when the binding flickers.
            .sheet(item: $shareCoordinator.pendingWeeklyShare) { result in
                ShareResultsSheet(source: .weekly(result))
                    .environmentObject(xAuthService)
            }
            .sheet(item: $shareCoordinator.pendingSeasonShare) { standing in
                ShareResultsSheet(source: .season(standing))
                    .environmentObject(xAuthService)
            }
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
