import Foundation

enum AuthRootDestination: Equatable {
    case loading
    case signIn
    case onboarding
    case main
}

enum AuthRouting {
    static func destination(
        authStateDetermined: Bool,
        isAuthenticated: Bool,
        needsOnboarding: Bool
    ) -> AuthRootDestination {
        guard authStateDetermined else { return .loading }
        guard isAuthenticated else { return .signIn }
        return needsOnboarding ? .onboarding : .main
    }

    static func needsOnboarding(
        userId: String?,
        hasGroup: Bool,
        hasCompletedOnboarding: Bool
    ) -> Bool {
        guard userId != nil else { return true }
        return !hasGroup && !hasCompletedOnboarding
    }
}
