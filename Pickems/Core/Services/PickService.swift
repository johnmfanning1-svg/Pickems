import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
@Observable
final class PickService {
    var nominations: [Nomination] = []
    var slateGames: [SlateGame] = []
    var userPick: UserPick?
    var allPicks: [UserPick] = []
    var submissions: [PickSubmission] = []
    var isLoading = false
    var errorMessage: String?

    /// Lazy so constructing `AppState` cannot touch Firestore before Firebase configure.
    @ObservationIgnored
    @ObservationIgnored private lazy var db = Firestore.firestore()
    @ObservationIgnored
    private var nominationsListener: ListenerRegistration?
    @ObservationIgnored
    private var gamesListener: ListenerRegistration?
    @ObservationIgnored
    private var pickListener: ListenerRegistration?
    @ObservationIgnored
    private var submissionsListener: ListenerRegistration?

    func observeWeek(groupId: String, weekId: String, userId: String) {
        nominationsListener?.remove()
        gamesListener?.remove()
        pickListener?.remove()
        submissionsListener?.remove()

        nominationsListener = db.week(groupId: groupId, weekId: weekId)
            .nominations
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        UserFacingError.apply(error, to: &self.errorMessage, context: .listener)
                        AppEvents.failure(.picksListenerError, error: error, metadata: [
                            "listener": "nominations",
                            "group_id": groupId,
                            "week_id": weekId,
                        ], recordNonFatal: false)
                        return
                    }
                    self.nominations = snapshot?.documents.compactMap { try? $0.data(as: Nomination.self) } ?? []
                }
            }

        gamesListener = db.week(groupId: groupId, weekId: weekId)
            .games
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        UserFacingError.apply(error, to: &self.errorMessage, context: .listener)
                        AppEvents.failure(.picksListenerError, error: error, metadata: [
                            "listener": "games",
                            "group_id": groupId,
                            "week_id": weekId,
                        ], recordNonFatal: false)
                        return
                    }
                    self.slateGames = snapshot?.documents.compactMap { try? $0.data(as: SlateGame.self) } ?? []
                }
            }

        pickListener = db.week(groupId: groupId, weekId: weekId)
            .picks.document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        UserFacingError.apply(error, to: &self.errorMessage, context: .listener)
                        AppEvents.failure(.picksListenerError, error: error, metadata: [
                            "listener": "user_pick",
                            "group_id": groupId,
                            "week_id": weekId,
                        ], recordNonFatal: false)
                        return
                    }
                    let pick = try? snapshot?.data(as: UserPick.self)
                    self.userPick = pick
                    // Pre-deadline list queries fail; keep own pick visible in Group Picks.
                    self.mergeOwnPickIntoAllPicks(pick)
                }
            }

        submissionsListener = db.week(groupId: groupId, weekId: weekId)
            .collection(FirestoreCollection.submissions)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        UserFacingError.apply(error, to: &self.errorMessage, context: .listener)
                        AppEvents.failure(.picksListenerError, error: error, metadata: [
                            "listener": "submissions",
                            "group_id": groupId,
                            "week_id": weekId,
                        ], recordNonFatal: false)
                        return
                    }
                    self.submissions = snapshot?.documents.compactMap {
                        try? $0.data(as: PickSubmission.self)
                    } ?? []
                }
            }
    }

    func loadAllPicks(groupId: String, weekId: String) async {
        do {
            let snapshot = try await db.collection("groups").document(groupId)
                .collection("weeks").document(weekId)
                .collection("picks").getDocuments()
            allPicks = snapshot.documents.compactMap { try? $0.data(as: UserPick.self) }
            // Ensure own pick stays present even if the list snapshot raced ahead of a write.
            mergeOwnPickIntoAllPicks(userPick)
            if let current = errorMessage, UserFacingError.looksLikePermissionMessage(current) {
                errorMessage = nil
            }
        } catch {
            // Before lock/deadline, rules hide other members' picks — expected, not a user error.
            // Collection list fails; explicitly get picks/{uid} (readable for self) and merge.
            if UserFacingError.isPermissionDenied(error) {
                // Keep only self while list is denied — never drop an in-memory own pick before get.
                let ownId = Auth.auth().currentUser?.uid
                allPicks = allPicks.filter { $0.userId == ownId }
                mergeOwnPickIntoAllPicks(userPick)
                await fetchAndMergeOwnPick(groupId: groupId, weekId: weekId)
                AppLog.notice(AppLog.firestore, "loadAllPicks deferred until picks are public", metadata: [
                    "group_id": groupId,
                    "week_id": weekId,
                    "own_pick_loaded": allPicks.isEmpty ? "false" : "true",
                ])
                if let current = errorMessage, UserFacingError.looksLikePermissionMessage(current) {
                    errorMessage = nil
                }
                return
            }
            UserFacingError.apply(error, to: &errorMessage)
        }
    }

    /// Upserts the signed-in member's pick into `allPicks` without wiping other entries.
    func mergeOwnPickIntoAllPicks(_ pick: UserPick?) {
        guard let pick else { return }
        if let idx = allPicks.firstIndex(where: { $0.userId == pick.userId }) {
            allPicks[idx] = pick
        } else {
            allPicks.append(pick)
        }
    }

    /// Document get for `picks/{currentUid}` — allowed pre-deadline when collection list is not.
    private func fetchAndMergeOwnPick(groupId: String, weekId: String) async {
        let uid = Auth.auth().currentUser?.uid
        if let uid {
            do {
                let snapshot = try await db.week(groupId: groupId, weekId: weekId)
                    .picks.document(uid)
                    .getDocument()
                if snapshot.exists, let pick = try? snapshot.data(as: UserPick.self) {
                    userPick = pick
                    mergeOwnPickIntoAllPicks(pick)
                    return
                }
            } catch {
                AppLog.notice(AppLog.firestore, "fetchAndMergeOwnPick get failed", metadata: [
                    "group_id": groupId,
                    "week_id": weekId,
                    "error": error.localizedDescription,
                ])
            }
        }
        mergeOwnPickIntoAllPicks(userPick)
    }

    func submitNomination(
        groupId: String,
        weekId: String,
        nomination: Nomination,
        rules: GroupRules
    ) async throws {
        let existing = nominations.filter { $0.espnEventId == nomination.espnEventId }
        guard existing.isEmpty else {
            throw PickError.duplicateGame
        }

        let userCount = nominations.filter { $0.submittedBy == nomination.submittedBy }.count
        guard ScoringEngine.canSubmitNomination(
            userNominationCount: userCount,
            selectionsPerMember: rules.selectionsPerMember,
            totalNominations: nominations.count,
            slateSize: rules.slateSize
        ) else {
            throw PickError.nominationLimitReached
        }

        let ref = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("nominations").document()

        var nom = nomination
        nom.id = ref.documentID
        try await ref.setData(from: nom)

        let weekRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)

        let weekSnapshot = try await weekRef.getDocument()
        let currentCount = weekSnapshot.data()?["nominationCount"] as? Int ?? nominations.count
        let newCount = currentCount + 1
        let allKickoffs = (nominations + [nomination]).map(\.kickoff)

        if ScoringEngine.isSlateComplete(nominationCount: newCount, slateSize: rules.slateSize) {
            try await materializeNominationsIfNeeded(groupId: groupId, weekId: weekId)
            // Open picking + set deadline from kickoffs; do not lock the slate yet.
            try await transitionToPicking(
                groupId: groupId,
                weekId: weekId,
                rules: rules,
                kickoffs: allKickoffs,
                nominationCount: newCount,
                lockSlate: false
            )
        } else {
            try await weekRef.updateData(["nominationCount": newCount])
        }
    }

    /// Converts nominations into slate games when the games collection is empty.
    func materializeNominationsIfNeeded(groupId: String, weekId: String) async throws {
        let weekRef = db.collection("groups").document(groupId).collection("weeks").document(weekId)
        let gamesSnap = try await weekRef.collection("games").getDocuments()
        guard gamesSnap.documents.isEmpty else { return }

        let nomsSnap = try await weekRef.collection("nominations").getDocuments()
        let nominations = nomsSnap.documents.compactMap { try? $0.data(as: Nomination.self) }
        var seenEventIds = Set<String>()
        for nom in nominations {
            if seenEventIds.contains(nom.espnEventId) {
                AppLog.notice(AppLog.picks, "materializeNominations skipped duplicate espnEventId", metadata: [
                    "espnEventId": nom.espnEventId,
                    "groupId": groupId,
                    "weekId": weekId
                ])
                continue
            }
            seenEventIds.insert(nom.espnEventId)
            let game = SlateGame(
                id: nom.espnEventId,
                espnEventId: nom.espnEventId,
                homeTeamId: nom.homeTeamId ?? "home",
                homeTeamName: nom.homeTeamName,
                homeTeamAbbreviation: nom.homeTeamAbbreviation ?? String(nom.homeTeamName.prefix(4)).uppercased(),
                homeTeamLogoURL: nom.homeTeamLogoURL,
                awayTeamId: nom.awayTeamId ?? "away",
                awayTeamName: nom.awayTeamName,
                awayTeamAbbreviation: nom.awayTeamAbbreviation ?? String(nom.awayTeamName.prefix(4)).uppercased(),
                awayTeamLogoURL: nom.awayTeamLogoURL,
                spread: abs(nom.spread),
                spreadTeamId: nom.spreadTeamId,
                kickoff: nom.kickoff,
                status: .scheduled,
                homeScore: nil,
                awayScore: nil,
                winnerTeamId: nil
            )
            try await weekRef.collection("games").document(game.id).setData(from: game)
        }
    }

    func removeNomination(
        groupId: String,
        weekId: String,
        nomination: Nomination,
        rules: GroupRules,
        isCommissioner: Bool,
        userId: String
    ) async throws {
        guard isCommissioner || nomination.submittedBy == userId else {
            throw PickError.unauthorized
        }

        try await db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("nominations").document(nomination.id)
            .delete()

        let weekRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
        try await weekRef.updateData(["nominationCount": FieldValue.increment(Int64(-1))])
    }

    func submitCommissionerGame(
        groupId: String,
        weekId: String,
        game: SlateGame,
        rules: GroupRules
    ) async throws {
        guard slateGames.count < rules.slateSize else {
            throw PickError.slateFull
        }
        guard !slateGames.contains(where: { $0.espnEventId == game.espnEventId }) else {
            throw PickError.duplicateGame
        }
        guard !nominations.contains(where: { $0.espnEventId == game.espnEventId }) else {
            throw PickError.duplicateGame
        }
        let ref = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("games").document(game.id)
        try await ref.setData(from: game)

        let allKickoffs = (slateGames + [game]).map(\.kickoff)
        if slateGames.count + 1 >= rules.slateSize {
            // Open picking + set deadline from kickoffs; do not lock the slate yet.
            try await transitionToPicking(
                groupId: groupId,
                weekId: weekId,
                rules: rules,
                kickoffs: allKickoffs,
                nominationCount: nil,
                lockSlate: false
            )
        }
    }

    private func transitionToPicking(
        groupId: String,
        weekId: String,
        rules: GroupRules,
        kickoffs: [Date],
        nominationCount: Int?,
        lockSlate: Bool = false
    ) async throws {
        let updates = WeekTransition.toPickingUpdates(
            rules: rules,
            kickoffs: kickoffs,
            nominationCount: nominationCount,
            setDeadline: true,
            lockSlate: lockSlate
        )
        try await db.week(groupId: groupId, weekId: weekId).updateData(updates)
    }

    func savePickDraft(
        groupId: String,
        weekId: String,
        userId: String,
        displayName: String,
        picks: [String: String],
        confidenceGameId: String? = nil
    ) async throws {
        let ref = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("picks").document(userId)

        let pick = UserPick(
            id: userId,
            userId: userId,
            displayName: displayName,
            picks: picks,
            submittedAt: nil,
            isLocked: false,
            confidenceGameId: confidenceGameId
        )
        try await ref.setData(from: pick)
        userPick = pick
        mergeOwnPickIntoAllPicks(pick)
        try await syncSubmission(
            groupId: groupId,
            weekId: weekId,
            userId: userId,
            displayName: displayName,
            isLocked: false,
            submittedAt: nil
        )
    }

    func submitPicks(
        groupId: String,
        weekId: String,
        userId: String,
        displayName: String,
        picks: [String: String],
        deadline: Date?,
        confidenceGameId: String? = nil,
        allowLatePicks: Bool = false
    ) async throws {
        if ScoringEngine.isPastDeadline(deadline: deadline), !allowLatePicks {
            throw PickError.deadlinePassed
        }
        let requiredGameIds = Set(slateGames.map(\.id))
        guard Set(picks.keys) == requiredGameIds else {
            throw PickError.incompletePicks
        }

        let ref = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("picks").document(userId)

        let pick = UserPick(
            id: userId,
            userId: userId,
            displayName: displayName,
            picks: picks,
            submittedAt: Date(),
            isLocked: true,
            confidenceGameId: confidenceGameId
        )
        try await ref.setData(from: pick)
        userPick = pick
        mergeOwnPickIntoAllPicks(pick)
        try await syncSubmission(
            groupId: groupId,
            weekId: weekId,
            userId: userId,
            displayName: displayName,
            isLocked: true,
            submittedAt: pick.submittedAt
        )
    }

    private func syncSubmission(
        groupId: String,
        weekId: String,
        userId: String,
        displayName: String,
        isLocked: Bool,
        submittedAt: Date?
    ) async throws {
        let submission = PickSubmission(
            id: userId,
            userId: userId,
            displayName: displayName,
            isLocked: isLocked,
            submittedAt: submittedAt
        )
        try await db.week(groupId: groupId, weekId: weekId)
            .collection(FirestoreCollection.submissions)
            .document(userId)
            .setData(from: submission)
    }

    func removeCommissionerGame(
        groupId: String,
        weekId: String,
        gameId: String,
        week: WeekSummary
    ) async throws {
        guard WeekTransition.isSlateEditable(week) else {
            throw PickError.cannotModifyLockedSlate
        }
        try await db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("games").document(gameId)
            .delete()
    }

    /// Commissioner wipe or force-write of another member's picks for the week.
    func commissionerSetPicks(
        groupId: String,
        weekId: String,
        userId: String,
        displayName: String,
        picks: [String: String],
        isLocked: Bool
    ) async throws {
        let pick = UserPick(
            id: userId,
            userId: userId,
            displayName: displayName,
            picks: picks,
            submittedAt: isLocked ? Date() : nil,
            isLocked: isLocked,
            confidenceGameId: nil
        )
        let pickRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("picks").document(userId)
        // Full replace so wiped keys actually disappear (merge cannot clear map entries).
        try await pickRef.setData(from: pick)
        try await syncSubmission(
            groupId: groupId,
            weekId: weekId,
            userId: userId,
            displayName: displayName,
            isLocked: isLocked,
            submittedAt: pick.submittedAt
        )
        if picks.isEmpty && !isLocked {
            allPicks.removeAll { $0.userId == userId }
        } else if allPicks.contains(where: { $0.userId == userId }) {
            allPicks = allPicks.map { $0.userId == userId ? pick : $0 }
        } else {
            allPicks.append(pick)
        }
        if userPick?.userId == userId {
            userPick = picks.isEmpty && !isLocked ? nil : pick
        }
    }

    func commissionerClearPicks(
        groupId: String,
        weekId: String,
        userId: String,
        displayName: String
    ) async throws {
        try await commissionerSetPicks(
            groupId: groupId,
            weekId: weekId,
            userId: userId,
            displayName: displayName,
            picks: [:],
            isLocked: false
        )
    }

    func updateGameSpread(
        groupId: String,
        weekId: String,
        gameId: String,
        spread: Double,
        spreadTeamId: String
    ) async throws {
        try await db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("games").document(gameId)
            .updateData([
                "spread": spread,
                "spreadTeamId": spreadTeamId
            ])
    }

    func bulkImportGames(
        groupId: String,
        weekId: String,
        games: [SlateGame],
        rules: GroupRules
    ) async throws {
        let gamesRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("games")
        let existingSnap = try await gamesRef.getDocuments()
        let existing = existingSnap.documents.compactMap { try? $0.data(as: SlateGame.self) }
        let existingIds = Set(existing.map(\.espnEventId))
        let remaining = rules.slateSize - existing.count
        guard remaining > 0 else { throw PickError.slateFull }

        var added: [SlateGame] = []
        for game in games {
            guard added.count < remaining else { break }
            guard !existingIds.contains(game.espnEventId) else { continue }
            guard !added.contains(where: { $0.espnEventId == game.espnEventId }) else { continue }
            try await gamesRef.document(game.id).setData(from: game)
            added.append(game)
        }

        let newCount = existing.count + added.count
        if newCount >= rules.slateSize {
            let allKickoffs = (existing + added).map(\.kickoff)
            try await transitionToPicking(
                groupId: groupId,
                weekId: weekId,
                rules: rules,
                kickoffs: allKickoffs,
                nominationCount: nil,
                lockSlate: false
            )
        }
    }

    func loadWeekHistory(groupId: String, weekId: String, userId: String) async throws -> WeekHistoryEntry? {
        let weekRef = db.collection("groups").document(groupId).collection("weeks").document(weekId)
        let weekDoc = try await weekRef.getDocument()
        guard let week = try? weekDoc.data(as: WeekSummary.self) else { return nil }

        let gamesSnap = try await weekRef.collection("games").getDocuments()
        let games = gamesSnap.documents.compactMap { try? $0.data(as: SlateGame.self) }

        let pickDoc = try await weekRef.collection("picks").document(userId).getDocument()
        let pick = try? pickDoc.data(as: UserPick.self)

        return WeekHistoryEntry(id: weekId, week: week, userPick: pick, slateGames: games)
    }

    enum PickError: LocalizedError {
        case duplicateGame
        case nominationLimitReached
        case slateFull
        case deadlinePassed
        case incompletePicks
        case unauthorized
        case cannotModifyLockedSlate

        var errorDescription: String? {
            switch self {
            case .duplicateGame: return "This game has already been nominated."
            case .nominationLimitReached: return "You've reached your nomination limit."
            case .slateFull: return "The slate is full."
            case .deadlinePassed: return "The pick deadline has passed."
            case .incompletePicks: return "Please pick every game before submitting."
            case .unauthorized: return "You can't remove this nomination."
            case .cannotModifyLockedSlate: return "The slate is locked — games can't be removed."
            }
        }
    }
}
