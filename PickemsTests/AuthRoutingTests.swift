import Foundation
import Testing
@testable import Pickems

struct AuthRoutingTests {
    @Test func loadingUntilAuthStateDetermined() {
        #expect(
            AuthRouting.destination(
                authStateDetermined: false,
                isAuthenticated: false,
                needsOnboarding: true
            ) == .loading
        )
    }

    @Test func signedOutShowsSignIn() {
        #expect(
            AuthRouting.destination(
                authStateDetermined: true,
                isAuthenticated: false,
                needsOnboarding: true
            ) == .signIn
        )
    }

    @Test func authenticatedWithoutLeagueShowsOnboarding() {
        #expect(
            AuthRouting.destination(
                authStateDetermined: true,
                isAuthenticated: true,
                needsOnboarding: true
            ) == .onboarding
        )
    }

    @Test func authenticatedReadyShowsMain() {
        #expect(
            AuthRouting.destination(
                authStateDetermined: true,
                isAuthenticated: true,
                needsOnboarding: false
            ) == .main
        )
    }

    @Test func needsOnboardingWithoutUser() {
        #expect(
            AuthRouting.needsOnboarding(
                userId: nil,
                hasGroup: false,
                hasCompletedOnboarding: false
            )
        )
    }

    @Test func needsOnboardingUntilLeagueOrFlag() {
        #expect(
            AuthRouting.needsOnboarding(
                userId: "u1",
                hasGroup: false,
                hasCompletedOnboarding: false
            )
        )
        #expect(
            !AuthRouting.needsOnboarding(
                userId: "u1",
                hasGroup: true,
                hasCompletedOnboarding: false
            )
        )
        #expect(
            !AuthRouting.needsOnboarding(
                userId: "u1",
                hasGroup: false,
                hasCompletedOnboarding: true
            )
        )
    }
}
