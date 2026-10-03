import Foundation
import Testing
@testable import Pickems

struct RollingLockSwitchTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func week(
        id: String = "2026-W5",
        status: WeekStatus,
        pickLockMode: DeadlinePolicy? = .firstKickoff,
        lockedAt: Date? = nil,
        kickoffOffsets: [TimeInterval]
    ) -> WeekSummary {
        var kickoffs: [String: Date] = [:]
        for (index, offset) in kickoffOffsets.enumerated() {
            kickoffs["game\(index)"] = now.addingTimeInterval(offset)
        }
        return WeekSummary(
            id: id,
            seasonYear: 2026,
            weekNumber: 5,
            status: status,
            slateSize: kickoffOffsets.count,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: lockedAt,
            pickDeadline: kickoffs.values.min(),
            pickLockMode: pickLockMode,
            weekLockAt: kickoffs.values.min(),
            gameKickoffs: kickoffs,
            nominationCount: kickoffOffsets.count
        )
    }

    @Test func lockedWeekWithGamesAheadPromptsToApply() {
        let locked = week(status: .locked, lockedAt: now.addingTimeInterval(-600), kickoffOffsets: [-1200, 3600, 7200])
        #expect(RollingLockSwitch.currentWeekPhase(locked, now: now) == .inProgress(weekId: "2026-W5"))
    }

    @Test func pickingWeekAfterFirstKickoffPromptsToApply() {
        let picking = week(status: .picking, kickoffOffsets: [-60, 3600])
        #expect(RollingLockSwitch.currentWeekPhase(picking, now: now) == .inProgress(weekId: "2026-W5"))
    }

    @Test func pickingWeekBeforeFirstKickoffJustChangesTheSetting() {
        let picking = week(status: .picking, kickoffOffsets: [3600, 7200])
        #expect(RollingLockSwitch.currentWeekPhase(picking, now: now) == .notInProgress)
    }

    @Test func selectionScoredAndMissingWeeksDoNotPrompt() {
        #expect(RollingLockSwitch.currentWeekPhase(nil, now: now) == .notInProgress)
        #expect(RollingLockSwitch.currentWeekPhase(week(status: .selection, kickoffOffsets: [-60]), now: now) == .notInProgress)
        #expect(RollingLockSwitch.currentWeekPhase(week(status: .scored, kickoffOffsets: [-60, 60]), now: now) == .notInProgress)
    }

    @Test func weekAlreadyOnRollingDoesNotPrompt() {
        let rolling = week(status: .picking, pickLockMode: .rolling, kickoffOffsets: [-60, 3600])
        #expect(RollingLockSwitch.currentWeekPhase(rolling, now: now) == .notInProgress)
    }

    @Test func everyGameStartedSkipsThePrompt() {
        let locked = week(status: .locked, lockedAt: now, kickoffOffsets: [-7200, -60])
        #expect(RollingLockSwitch.currentWeekPhase(locked, now: now) == .allGamesStarted)
    }

    @Test func leaguePhaseFindsTheInProgressWeekWhileBrowsingAnother() {
        let next = week(id: "2026-W6", status: .selection, kickoffOffsets: [])
        let current = week(id: "2026-W5", status: .locked, lockedAt: now, kickoffOffsets: [-60, 3600])
        let result = RollingLockSwitch.leaguePhase(weeks: [next, next, current], now: now)
        #expect(result.phase == .inProgress(weekId: "2026-W5"))
        #expect(result.week?.id == "2026-W5")
        #expect(RollingLockSwitch.leaguePhase(weeks: [next], now: now).phase == .notInProgress)
    }

    @Test func disclaimerCoversEveryWarning() {
        let message = RollingLockSwitch.promptMessage
        #expect(message.contains("visible to the league since this week locked"))
        #expect(message.contains("change picks on games that haven't started"))
        #expect(message.contains("Games that have started stay locked"))
        #expect(message.contains("misses counts as a loss"))
        #expect(RollingLockSwitch.disclaimerPoints.count == 4)
    }

    @Test func callableErrorEnvelopeSurfacesServerMessage() throws {
        let body = Data(#"{"error":{"status":"FAILED_PRECONDITION","message":"That week is already final."}}"#.utf8)
        #expect(throws: CloudFunctionsClient.CallableError(
            status: "FAILED_PRECONDITION",
            message: "That week is already final."
        )) {
            try CloudFunctionsClient.parse(body: body, statusCode: 400)
        }
    }

    @Test func callableResultAndMissingFunctionAreHandled() throws {
        let ok = Data(#"{"result":{"weekChanged":true}}"#.utf8)
        let result = try CloudFunctionsClient.parse(body: ok, statusCode: 200)
        #expect(result["weekChanged"] as? Bool == true)

        #expect(throws: CloudFunctionsClient.CallableError.self) {
            try CloudFunctionsClient.parse(body: Data("Not Found".utf8), statusCode: 404)
        }
        #expect(CloudFunctionsClient.url(projectID: "pickems-fb", function: "setRollingLock")?.absoluteString
            == "https://us-central1-pickems-fb.cloudfunctions.net/setRollingLock")
    }
}
