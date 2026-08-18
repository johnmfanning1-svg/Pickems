import Foundation
import Testing
@testable import Pickems

struct UserFacingErrorTests {
    @Test func cancellationIsNotShownToUsers() {
        #expect(UserFacingError.isCancellation(CancellationError()))
        #expect(UserFacingError.message(for: CancellationError()) == nil)

        let urlCancelled = URLError(.cancelled)
        #expect(UserFacingError.isCancellation(urlCancelled))
        #expect(UserFacingError.message(for: urlCancelled) == nil)

        let nsCancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        #expect(UserFacingError.isCancellation(nsCancelled))
        #expect(UserFacingError.message(for: nsCancelled) == nil)
    }

    @Test func applyClearsBannerOnCancellation() {
        var banner: String? = "stale"
        UserFacingError.apply(CancellationError(), to: &banner)
        #expect(banner == nil)
    }

    @Test func genericFailuresStillSurface() {
        let error = NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Couldn't reach ESPN",
        ])
        #expect(UserFacingError.message(for: error) == "Couldn't reach ESPN")
    }
}
