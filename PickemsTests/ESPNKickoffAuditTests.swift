import Foundation
import Testing
@testable import Pickems

struct ESPNKickoffAuditTests {
    @Test func easternOffsetAndZuluAreTheSameInstant() {
        let zulu = ESPNService.parseKickoffDate("2026-11-01T05:30:00Z")
        let eastern = ESPNService.parseKickoffDate("2026-11-01T01:30:00-04:00")
        #expect(zulu == eastern)
        let afterFallback = ESPNService.parseKickoffDate("2026-11-01T01:30:00-05:00")
        #expect(afterFallback != zulu)
    }

    @Test func localClockWithoutAZoneIsRejected() {
        #expect(ESPNService.parseKickoffDate("2026-11-01T01:30:00") == nil)
        #expect(ESPNService.parseKickoffDate("2026-11-01 01:30") == nil)
    }

    @Test func minutePrecisionWithOffsetLocksTheSameInstant() {
        let offset = ESPNService.parseKickoffDate("2026-09-05T15:00-04:00")
        let zulu = ESPNService.parseKickoffDate("2026-09-05T19:00:00Z")
        #expect(offset == zulu)
    }
}
