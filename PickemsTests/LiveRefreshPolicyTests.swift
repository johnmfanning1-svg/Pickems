import Foundation
import Testing
@testable import Pickems

struct LiveRefreshPolicyTests {
    @Test func homePollsOnlyWhileThatTabIsActive() {
        #expect(LiveRefreshPolicy.shouldPollLiveScores(isHomeTab: true, isActive: true))
        #expect(!LiveRefreshPolicy.shouldPollLiveScores(isHomeTab: true, isActive: false))
        #expect(!LiveRefreshPolicy.shouldPollLiveScores(isHomeTab: false, isActive: true))
        #expect(!LiveRefreshPolicy.shouldPollLiveScores(isHomeTab: false, isActive: false))
    }
}
