import Foundation

enum AuthRootDestination: Equatable, CustomStringConvertible {
    case loading
    case signIn
    case onboarding
    case main

    var description: String {
        switch self {
        case .loading: return "loading"
        case .signIn: return "signIn"
        case .onboarding: return "onboarding"
        case .main: return "main"
        }
    }
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
        hasCompletedOnboarding: Bool = false
    ) -> Bool {
        // Join/create is optional: once the user skips (or finishes) onboarding,
        // send them to main even without a league. Home still offers Join/Create.
        guard userId != nil else { return true }
        if hasGroup || hasCompletedOnboarding { return false }
        return true
    }
}
