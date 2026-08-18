import Foundation
import Testing
@testable import Pickems

struct ForceUpdatePolicyTests {
    @Test func missingOrZeroMinimumDoesNotBlock() {
        #expect(!ForceUpdatePolicy.requiresUpdate(currentBuild: 223, minimumBuild: nil))
        #expect(ForceUpdatePolicy.parseMinimumBuild(nil) == nil)
        #expect(ForceUpdatePolicy.parseMinimumBuild(NSNull()) == nil)
        #expect(ForceUpdatePolicy.parseMinimumBuild(0) == nil)
        #expect(ForceUpdatePolicy.parseMinimumBuild(-1) == nil)
    }

    @Test func currentBuildAtOrAboveMinimumIsAllowed() {
        #expect(!ForceUpdatePolicy.requiresUpdate(currentBuild: 259, minimumBuild: 259))
        #expect(!ForceUpdatePolicy.requiresUpdate(currentBuild: 260, minimumBuild: 259))
    }

    @Test func olderBuildIsBlocked() {
        #expect(ForceUpdatePolicy.requiresUpdate(currentBuild: 223, minimumBuild: 259))
        #expect(ForceUpdatePolicy.requiresUpdate(currentBuild: 258, minimumBuild: 259))
    }

    @Test func parsesFirestoreNumberAndStringShapes() {
        #expect(ForceUpdatePolicy.parseMinimumBuild(259) == 259)
        #expect(ForceUpdatePolicy.parseMinimumBuild(NSNumber(value: 259)) == 259)
        #expect(ForceUpdatePolicy.parseMinimumBuild("259") == 259)
        #expect(ForceUpdatePolicy.parseMinimumBuild(" 259 ") == 259)
        #expect(ForceUpdatePolicy.parseMinimumBuild("nope") == nil)
    }
}
