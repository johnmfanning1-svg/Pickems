import Foundation

/// Ordered commissioner writes after Reopen Selections (+ optional new deadline).
enum ReopenSelectionsWriter {
    enum Outcome: Equatable {
        case completed
        case deadlineSaveFailed
    }

    static func perform(
        deadline: Date?,
        groupId: String,
        weekId: String,
        userId: String,
        commissionerName: String,
        reopenWeekForSelections: (String, String) async throws -> Void,
        setSelectionDeadline: (String, String, Date, String) async throws -> Void,
        clearSlateGamesForSelectionReopen: (String, String, String, String) async throws -> Void
    ) async throws -> Outcome {
        try await reopenWeekForSelections(groupId, weekId)
        if let deadline {
            do {
                try await setSelectionDeadline(groupId, weekId, deadline, userId)
            } catch {
                return .deadlineSaveFailed
            }
        }
        try await clearSlateGamesForSelectionReopen(
            groupId,
            weekId,
            userId,
            commissionerName
        )
        return .completed
    }
}