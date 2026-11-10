import Foundation
import Testing
@testable import Pickems

struct LeagueSearchJoinTests {
    @Test func opensTheExistingJoinSheet() {
        #expect(LeagueSearchJoin.sheet == .joinGroup)
        #expect(LeagueSearchJoin.sheet.id == "joinGroup")
        #expect(LeagueSearchJoin.sheet != .createLeague)
    }

    @Test func usesMagnifyingGlassAndSearchJoinLabel() {
        #expect(LeagueSearchJoin.systemImage == "magnifyingglass")
        #expect(LeagueSearchJoin.accessibilityLabel == "Search or join a league")
        #expect(LeagueSearchJoin.accessibilityHint == "Enter an invite code from your commissioner")
    }
}
