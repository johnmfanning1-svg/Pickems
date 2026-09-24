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

    @Test func firestoreSourceServerDumpMapsToFriendlyRefreshCopy() {
        // Exact class of SDK string from John's screenshot (server-only refresh hop).
        let sdkDump = "Failed to get document because the client is offline. FirestoreSourceServer"
        let error = NSError(domain: "FIRFirestoreErrorDomain", code: 14, userInfo: [
            NSLocalizedDescriptionKey: sdkDump,
        ])
        #expect(UserFacingError.isServerSourceUnavailable(error))
        #expect(UserFacingError.message(for: error) == UserFacingError.refreshUnavailableMessage)
        #expect(UserFacingError.refreshUnavailableMessage ==
                "Couldn't refresh right now. Pull to refresh or try again in a moment.")
    }

    @Test func failedToGetDocumentsFromServerMapsToFriendlyCopy() {
        let sdkDump = "Failed to get documents from server. (FirestoreSourceServer)"
        #expect(UserFacingError.looksLikeServerSourceUnavailableCopy(sdkDump))
        let error = NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: sdkDump,
        ])
        #expect(UserFacingError.message(for: error) == UserFacingError.refreshUnavailableMessage)
    }

    @Test func clientOfflineCopyIsTreatedAsServerUnavailable() {
        let copy = "Failed to get document because the client is offline."
        #expect(UserFacingError.looksLikeServerSourceUnavailableCopy(copy))
    }

    @Test func applySetsFriendlyRefreshBannerForServerUnavailable() {
        var banner: String? = nil
        let error = NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to get document(s) from server. FirestoreSourceServer",
        ])
        UserFacingError.apply(error, to: &banner)
        #expect(banner == UserFacingError.refreshUnavailableMessage)
    }
}
