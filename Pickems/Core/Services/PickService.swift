import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
@Observable
final class PickService {
    var nominations: [Nomination] = []
    var slateGames: [SlateGame] = []
    /// Games plus any nominations not already on the slate — used while `.selection`
    /// after Reopen, when commissioner-mode games may have been copied to noms.
    var displaySlateGames: [SlateGame] {
        SlateGameDecoding.mergedSlate(games: slateGames, nominations: nominations)
    }
    var userPick: UserPick?
    /// Bumped when a local commissioner set/clear (or week reset) must beat a
    /// pending Picks-tab draft, including empty wipes from Group Pickems.
    private(set) var userPickEpoch = 0
    /// Shared Selections "submitted" ack so Groups and the Picks tab cannot diverge.
    private(set) var didSubmitNominations = false
    var allPicks: [UserPick] = []
    var submissions: [PickSubmission] = []
    var isLoading = false
    var errorMessage: String?

    /// Lazy so constructing `AppState` cannot touch Firestore before Firebase configure.
    @ObservationIgnored
    private lazy var db = Firestore.firestore()
    @ObservationIgnored
    private var nominationsListener: ListenerRegistration?
    @ObservationIgnored
    private var gamesListener: ListenerRegistration?
    @ObservationIgnored
    private var pickListener: ListenerRegistration?
    @ObservationIgnored
    private var submissionsListener: ListenerRegistration?
    @ObservationIgnored
    private var observedUserId: String?
    /// Invalidates in-flight `savePickDraft` local mirrors after a later clear/set.
    @ObservationIgnored
    private var userPickWriteGeneration = 0

    func observeWeek(groupId: String, weekId: String, userId: String) {
        nominationsListener?.remove()
        gamesListener?.remove()
        pickListener?.remove()
        submissionsListener?.remove()
        nominations = []
        slateGames = []
        observedUserId = userId
        userPickWriteGeneration += 1
        userPick = nil
        userPickEpoch += 1
        allPicks = []
        submissions = []
        refreshNominationSubmissionState(groupId: groupId, weekId: weekId, userId: userId)

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
                    self.slateGames = SlateGameDecoding.sortedByKickoff(
                        snapshot?.documents.compactMap { doc in
                            SlateGame.fromDocument(id: doc.documentID, data: doc.data())
                        } ?? []
                    )
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
                    if let pick, !pick.picks.isEmpty {
                        Task { await self.reconcileOwnSubmissionPickCount(
                            groupId: groupId,
                            weekId: weekId,
                            pick: pick
                        ) }
                    }
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

    func resetSession() {
        nominationsListener?.remove()
        gamesListener?.remove()
        pickListener?.remove()
        submissionsListener?.remove()
        nominationsListener = nil
        gamesListener = nil
        pickListener = nil
        submissionsListener = nil
        nominations = []
        slateGames = []
        observedUserId = nil
        userPickWriteGeneration += 1
        userPick = nil
        userPickEpoch += 1
        allPicks = []
        submissions = []
        didSubmitNominations = false
        errorMessage = nil
        isLoading = false
    }

    // MARK: - Selections submitted acknowledgement (shared)

    private func nominationsSubmittedKey(groupId: String, weekId: String, userId: String) -> String {
        "pickems.nominationsSubmitted.\(groupId).\(weekId).\(userId)"
    }

    func refreshNominationSubmissionState(groupId: String?, weekId: String?, userId: String?) {
        guard let groupId, let weekId, let userId else {
            didSubmitNominations = false
            return
        }
        didSubmitNominations = UserDefaults.standard.bool(
            forKey: nominationsSubmittedKey(groupId: groupId, weekId: weekId, userId: userId)
        )
    }

    func markNominationsSubmitted(groupId: String, weekId: String, userId: String) {
        UserDefaults.standard.set(
            true,
            forKey: nominationsSubmittedKey(groupId: groupId, weekId: weekId, userId: userId)
        )
        didSubmitNominations = true
    }

    func clearNominationsSubmitted(groupId: String, weekId: String, userId: String) {
        UserDefaults.standard.set(
            false,
            forKey: nominationsSubmittedKey(groupId: groupId, weekId: weekId, userId: userId)
        )
        didSubmitNominations = false
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
    /// Empty unlocked picks are removed so commissioner clears don't leave ghost rows.
    func mergeOwnPickIntoAllPicks(_ pick: UserPick?) {
        guard let pick else { return }
        if pick.picks.isEmpty && !pick.isLocked {
            allPicks.removeAll { $0.userId == pick.userId }
            return
        }
        if let idx = allPicks.firstIndex(where: { $0.userId == pick.userId }) {
            allPicks[idx] = pick
        } else {
            allPicks.append(pick)
        }
    }

    /// Backfill public `pickCount` on submissions written before that field existed,
    /// so Group Picks can show 3/3 without waiting for the week to lock.
    private func reconcileOwnSubmissionPickCount(
        groupId: String,
        weekId: String,
        pick: UserPick
    ) async {
        let existing = submissions.first { $0.userId == pick.userId }
        let needsCount = (existing?.pickCount ?? 0) < pick.picks.count
        let needsLock = pick.isLocked && existing?.isLocked != true
        guard needsCount || needsLock || existing == nil else { return }
        do {
            try await syncSubmission(
                groupId: groupId,
                weekId: weekId,
                userId: pick.userId,
                displayName: pick.displayName,
                isLocked: pick.isLocked,
                submittedAt: pick.submittedAt,
                pickCount: pick.picks.count
            )
        } catch {
            AppLog.notice(AppLog.firestore, "reconcileOwnSubmissionPickCount failed", metadata: [
                "group_id": groupId,
                "week_id": weekId,
                "error": error.localizedDescription,
            ])
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

    /// Drops blank game/team ids so a cleared Pickem is stored as "no pick", not a fake selection.
    nonisolated static func sanitizedPicks(_ picks: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: picks.compactMap { key, value in
            let gameId = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let teamId = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !gameId.isEmpty, !teamId.isEmpty else { return nil }
            return (gameId, teamId)
        })
    }

    func submitNomination(
        groupId: String,
        weekId: String,
        nomination: Nomination,
        rules: GroupRules,
        week: WeekSummary,
        memberIds _: [String]
    ) async throws {
        switch week.status {
        case .locked, .scored, .picking:
            // After lock-early or the Selection deadline, members cannot remake
            // Selections. Commissioner fill uses `submitCommissionerGame`.
            throw PickError.selectionClosed
        case .selection:
            guard WeekTransition.canRemakeSelections(week) else {
                throw PickError.selectionClosed
            }
        }
        let existingNoms = nominations.contains { $0.espnEventId == nomination.espnEventId }
        let existingGames = slateGames.contains { $0.espnEventId == nomination.espnEventId }
        guard !existingNoms, !existingGames else {
            throw PickError.duplicateGame
        }

        let slateSize = week.slateSize
        let perMember = week.selectionsPerMember > 0 ? week.selectionsPerMember : rules.selectionsPerMember
        let uniqueCount: Int
        if week.status == .picking {
            uniqueCount = Set(slateGames.map(\.espnEventId)).count
        } else {
            uniqueCount = Set(nominations.map(\.espnEventId) + slateGames.map(\.espnEventId)).count
        }
        let userCount = nominations.filter { $0.submittedBy == nomination.submittedBy }.count
        guard ScoringEngine.canSubmitNomination(
            userNominationCount: userCount,
            selectionsPerMember: perMember,
            uniqueNominationCount: uniqueCount,
            slateSize: slateSize,
            selectionDeadline: week.selectionDeadline
        ) else {
            throw PickError.nominationLimitReached
        }

        let ref = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("nominations").document()

        var nom = nomination
        nom.id = ref.documentID
        try await ref.setData(from: nom)
        nominations.append(nom)

        let weekRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
        // Completing Selections does not open Pickems. Stay in `.selection` so
        // members can clear and remake until the deadline or commissioner lock-early.
        try await weekRef.updateData(["nominationCount": nominations.count])
    }

    /// Copies nominations into `games` for any event that is not already on the slate.
    /// Does not overwrite existing game docs (spread edits stay).
    func materializeNominationsIfNeeded(groupId: String, weekId: String) async throws {
        let weekRef = db.collection("groups").document(groupId).collection("weeks").document(weekId)
        let gamesSnap = try await weekRef.collection("games").getDocuments()
        var seenEventIds = Set<String>()
        for doc in gamesSnap.documents {
            seenEventIds.insert(doc.documentID)
            if let game = SlateGame.fromDocument(id: doc.documentID, data: doc.data()) {
                seenEventIds.insert(game.espnEventId)
                seenEventIds.insert(game.id)
            }
        }

        let nomsSnap = try await weekRef.collection("nominations").getDocuments()
        let nominations = nomsSnap.documents.compactMap { try? $0.data(as: Nomination.self) }
        var seenFromNoms = Set<String>()
        for nom in nominations {
            if !seenFromNoms.insert(nom.espnEventId).inserted {
                AppLog.notice(AppLog.picks, "materializeNominations skipped duplicate espnEventId", metadata: [
                    "espnEventId": nom.espnEventId,
                    "groupId": groupId,
                    "weekId": weekId
                ])
                continue
            }
            if seenEventIds.contains(nom.espnEventId) { continue }
            seenEventIds.insert(nom.espnEventId)
            let game = nom.asSlateGame()
            try await weekRef.collection("games").document(game.id).setData(from: game)
            if !slateGames.contains(where: { $0.espnEventId == game.espnEventId || $0.id == game.id }) {
                slateGames.append(game)
            }
        }
    }

    func removeNomination(
        groupId: String,
        weekId: String,
        nomination: Nomination,
        rules: GroupRules,
        week: WeekSummary,
        isCommissioner: Bool,
        userId: String
    ) async throws {
        if nomination.submittedBy != userId {
            guard isCommissioner else { throw PickError.unauthorized }
            guard WeekTransition.isSlateEditable(week) else {
                throw PickError.cannotModifyLockedSlate
            }
        } else {
            guard WeekTransition.canRemakeSelections(week) else {
                throw PickError.selectionClosed
            }
        }

        let weekRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)

        try await weekRef.collection("nominations").document(nomination.id).delete()
        nominations.removeAll { $0.id == nomination.id }
        try await weekRef.updateData(["nominationCount": FieldValue.increment(Int64(-1))])

        // Clearing a Selection must drop the slate game too, or remake hits
        // duplicateGame and Pickems keeps showing the cleared game.
        // Materialize keys games by espnEventId; also sweep any other doc id.
        let eventId = nomination.espnEventId
        var gameIds = Set(
            slateGames
                .filter { $0.espnEventId == eventId || $0.id == eventId }
                .map(\.id)
        )
        gameIds.insert(eventId)
        if let extra = try? await weekRef.collection("games")
            .whereField("espnEventId", isEqualTo: eventId)
            .getDocuments() {
            for doc in extra.documents { gameIds.insert(doc.documentID) }
        }
        for gameId in gameIds {
            try? await weekRef.collection("games").document(gameId).delete()
        }
        slateGames.removeAll { $0.espnEventId == eventId || $0.id == eventId || gameIds.contains($0.id) }
        userPickEpoch += 1

        if nomination.submittedBy == userId {
            clearNominationsSubmitted(groupId: groupId, weekId: weekId, userId: userId)
        }
    }

    func submitCommissionerGame(
        groupId: String,
        weekId: String,
        game: SlateGame,
        rules: GroupRules,
        week: WeekSummary
    ) async throws {
        switch week.status {
        case .locked, .scored:
            throw PickError.cannotModifyLockedSlate
        case .picking:
            if ScoringEngine.isPastDeadline(deadline: week.pickDeadline) {
                throw PickError.cannotModifyLockedSlate
            }
        case .selection:
            break
        }

        let slateSize = week.slateSize > 0 ? week.slateSize : rules.slateSize
        // During picking the live slate is `games`; leftover nominations must not block a replacement.
        let currentCount: Int
        if week.status == .picking {
            currentCount = slateGames.count
        } else {
            currentCount = max(slateGames.count, Set(nominations.map(\.espnEventId)).count)
        }
        guard currentCount < slateSize else {
            throw PickError.slateFull
        }
        guard !slateGames.contains(where: { $0.espnEventId == game.espnEventId }) else {
            throw PickError.duplicateGame
        }
        if week.status != .picking {
            guard !nominations.contains(where: { $0.espnEventId == game.espnEventId }) else {
                throw PickError.duplicateGame
            }
        }

        // Ensure member nominations are on the slate before commissioner fill.
        if week.selectionMode == .member, week.status == .selection {
            try await materializeNominationsIfNeeded(groupId: groupId, weekId: weekId)
        }

        let ref = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("games").document(game.id)
        try await ref.setData(from: game)
        if !slateGames.contains(where: { $0.id == game.id }) {
            slateGames.append(game)
        }

        if week.status == .selection {
            try await db.week(groupId: groupId, weekId: weekId).updateData([
                "nominationCount": week.selectionMode == .member ? nominations.count : slateGames.count
            ])
        }
    }

    /// Drops materialized slate games after Reopen Selections so remake cannot
    /// hit `duplicateGame` on leftover games. Nominations stay and rematerialize
    /// the next time the commissioner opens the week.
    ///
    /// Commissioner-mode slates often have games and no nominations. Those games
    /// are copied to nominations first, then **kept** so Settings / Selections
    /// do not go empty. Member-mode (nominations already exist) still deletes games.
    func clearSlateGamesForSelectionReopen(
        groupId: String,
        weekId: String,
        commissionerUserId: String,
        commissionerName: String
    ) async throws {
        let weekRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
        let gamesSnap = try await weekRef.collection("games").getDocuments()
        let nomsSnap = try await weekRef.collection("nominations").getDocuments()
        let existingNomEventIds = Set(nomsSnap.documents.compactMap { doc -> String? in
            SlateGameDecoding.stringValue(doc.data()["espnEventId"])
        })

        var copied = 0
        for doc in gamesSnap.documents {
            guard let game = SlateGame.fromDocument(id: doc.documentID, data: doc.data()) else { continue }
            let eventId = game.espnEventId
            guard !eventId.isEmpty, !existingNomEventIds.contains(eventId) else { continue }
            let ref = weekRef.collection("nominations").document()
            var nom = Nomination(
                id: ref.documentID,
                submittedBy: commissionerUserId,
                submitterName: commissionerName,
                espnEventId: eventId,
                spread: game.spread,
                spreadTeamId: game.spreadTeamId,
                homeTeamId: game.homeTeamId,
                homeTeamName: game.homeTeamName,
                homeTeamAbbreviation: game.homeTeamAbbreviation,
                homeTeamLogoURL: game.homeTeamLogoURL,
                awayTeamId: game.awayTeamId,
                awayTeamName: game.awayTeamName,
                awayTeamAbbreviation: game.awayTeamAbbreviation,
                awayTeamLogoURL: game.awayTeamLogoURL,
                kickoff: game.kickoff,
                createdAt: Date()
            )
            nom.id = ref.documentID
            do {
                try await ref.setData(from: nom)
                if !nominations.contains(where: { $0.espnEventId == eventId }) {
                    nominations.append(nom)
                }
                copied += 1
            } catch {
                AppLog.notice(AppLog.picks, "reopen copied nomination failed", metadata: [
                    "espnEventId": eventId,
                    "error": error.localizedDescription
                ])
            }
        }
        if copied > 0 {
            try? await weekRef.updateData([
                "nominationCount": FieldValue.increment(Int64(copied))
            ])
        }

        // Member remake needs leftover games gone. Commissioner-mode (no noms
        // before this pass) keeps the game docs so the slate stays visible.
        let hadNominationsBeforeCopy = !existingNomEventIds.isEmpty
        guard hadNominationsBeforeCopy, !gamesSnap.documents.isEmpty else { return }

        let batch = db.batch()
        for doc in gamesSnap.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
        slateGames = []
        userPickEpoch += 1
    }

    /// Opens picking with whatever unique games/nominations exist (may be under slateSize).
    func openWeekWithCurrentSlate(
        groupId: String,
        weekId: String,
        rules: GroupRules
    ) async throws {
        try await materializeNominationsIfNeeded(groupId: groupId, weekId: weekId)
        let kickoffs = await slateKickoffs(
            groupId: groupId,
            weekId: weekId,
            fallback: nominations.map(\.kickoff) + slateGames.map(\.kickoff)
        )
        guard !kickoffs.isEmpty else {
            throw PickError.slateFull
        }
        try await transitionToPicking(
            groupId: groupId,
            weekId: weekId,
            rules: rules,
            kickoffs: kickoffs,
            nominationCount: nominations.count,
            lockSlate: true
        )
    }

    private func slateKickoffs(groupId: String, weekId: String, fallback: [Date]) async -> [Date] {
        let gamesSnap = try? await db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("games")
            .getDocuments()
        let fromGames = gamesSnap?.documents.compactMap { doc -> Date? in
            SlateGame.fromDocument(id: doc.documentID, data: doc.data())?.kickoff
        } ?? []
        return fromGames.isEmpty ? fallback : fromGames
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
        confidenceGameId: String? = nil,
        week: WeekSummary? = nil,
        allowLatePicks: Bool = false
    ) async throws {
        if let week {
            switch week.status {
            case .locked, .scored:
                throw PickError.deadlinePassed
            case .selection:
                throw PickError.pickemsNotOpen
            case .picking:
                if ScoringEngine.isPastDeadline(deadline: week.pickDeadline), !allowLatePicks {
                    throw PickError.deadlinePassed
                }
            }
        }

        let cleaned = Self.sanitizedPicks(picks)
        let validGameIds = Set(slateGames.map(\.id))
        let trimmed = validGameIds.isEmpty
            ? cleaned
            : cleaned.filter { validGameIds.contains($0.key) }
        let trimmedConfidence: String? = {
            guard let confidenceGameId, trimmed.keys.contains(confidenceGameId) else { return nil }
            return confidenceGameId
        }()

        let ref = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("picks").document(userId)

        // Clearing or editing Pickems never touches nominations or slate games.
        let pick = UserPick(
            id: userId,
            userId: userId,
            displayName: displayName,
            picks: trimmed,
            submittedAt: nil,
            isLocked: false,
            confidenceGameId: trimmedConfidence
        )
        let generation = userPickWriteGeneration
        try await ref.setData(from: pick)
        guard generation == userPickWriteGeneration else { return }
        userPick = pick
        mergeOwnPickIntoAllPicks(pick)
        try await syncSubmission(
            groupId: groupId,
            weekId: weekId,
            userId: userId,
            displayName: displayName,
            isLocked: false,
            submittedAt: nil,
            pickCount: trimmed.count
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
        let cleaned = Self.sanitizedPicks(picks).filter { requiredGameIds.contains($0.key) }
        guard Set(cleaned.keys) == requiredGameIds else {
            throw PickError.incompletePicks
        }

        let ref = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("picks").document(userId)

        let pick = UserPick(
            id: userId,
            userId: userId,
            displayName: displayName,
            picks: cleaned,
            submittedAt: Date(),
            isLocked: true,
            confidenceGameId: confidenceGameId.flatMap { cleaned.keys.contains($0) ? $0 : nil }
        )
        let generation = userPickWriteGeneration
        try await ref.setData(from: pick)
        guard generation == userPickWriteGeneration else { return }
        userPick = pick
        mergeOwnPickIntoAllPicks(pick)
        try await syncSubmission(
            groupId: groupId,
            weekId: weekId,
            userId: userId,
            displayName: displayName,
            isLocked: true,
            submittedAt: pick.submittedAt,
            pickCount: cleaned.count
        )
    }

    private func syncSubmission(
        groupId: String,
        weekId: String,
        userId: String,
        displayName: String,
        isLocked: Bool,
        submittedAt: Date?,
        pickCount: Int
    ) async throws {
        let submission = PickSubmission(
            id: userId,
            userId: userId,
            displayName: displayName,
            isLocked: isLocked,
            submittedAt: submittedAt,
            pickCount: pickCount
        )
        try await db.week(groupId: groupId, weekId: weekId)
            .collection(FirestoreCollection.submissions)
            .document(userId)
            .setData(from: submission)
        // Keep local mirror in sync so Group Picks updates immediately.
        if let idx = submissions.firstIndex(where: { $0.userId == userId }) {
            submissions[idx] = submission
        } else {
            submissions.append(submission)
        }
    }

    func removeCommissionerGame(
        groupId: String,
        weekId: String,
        gameId: String,
        week: WeekSummary
    ) async throws {
        switch week.status {
        case .locked, .scored:
            throw PickError.cannotModifyLockedSlate
        case .picking:
            if ScoringEngine.isPastDeadline(deadline: week.pickDeadline)
                || !WeekTransition.isSlateEditable(week) {
                throw PickError.cannotModifyLockedSlate
            }
        case .selection:
            break
        }
        let weekRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
        try await weekRef.collection("games").document(gameId).delete()

        let removed = slateGames.first { $0.id == gameId }
        slateGames.removeAll { $0.id == gameId }

        // Drop the matching Selection nomination so a replacement can be added.
        // Never called from Pickem clears — those only write the picks document.
        let eventId = removed?.espnEventId ?? gameId
        let matchingNoms = nominations.filter { $0.espnEventId == eventId }
        for nom in matchingNoms {
            try await weekRef.collection("nominations").document(nom.id).delete()
        }
        if !matchingNoms.isEmpty {
            nominations.removeAll { $0.espnEventId == eventId }
            try await weekRef.updateData([
                "nominationCount": FieldValue.increment(Int64(-matchingNoms.count))
            ])
        }
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
        let cleaned = Self.sanitizedPicks(picks)
        let pick = UserPick(
            id: userId,
            userId: userId,
            displayName: displayName,
            picks: cleaned,
            submittedAt: isLocked ? Date() : nil,
            isLocked: isLocked,
            confidenceGameId: nil
        )
        if userId == observedUserId {
            userPickWriteGeneration += 1
        }
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
            submittedAt: pick.submittedAt,
            pickCount: cleaned.count
        )
        if cleaned.isEmpty && !isLocked {
            allPicks.removeAll { $0.userId == userId }
        } else if allPicks.contains(where: { $0.userId == userId }) {
            allPicks = allPicks.map { $0.userId == userId ? pick : $0 }
        } else {
            allPicks.append(pick)
        }
        if userId == observedUserId {
            userPick = cleaned.isEmpty && !isLocked ? nil : pick
            userPickEpoch += 1
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

    /// Unlocks every member's submitted picks so they can edit again after a deadline extension.
    func commissionerUnlockAllPicks(groupId: String, weekId: String) async throws {
        let picksSnap = try await db.week(groupId: groupId, weekId: weekId)
            .collection(FirestoreCollection.picks)
            .getDocuments()
        guard !picksSnap.documents.isEmpty else { return }

        let batch = db.batch()
        for doc in picksSnap.documents {
            batch.updateData(
                [
                    "isLocked": false,
                    "submittedAt": FieldValue.delete(),
                ],
                forDocument: doc.reference
            )
            let submissionRef = db.week(groupId: groupId, weekId: weekId)
                .collection(FirestoreCollection.submissions)
                .document(doc.documentID)
            batch.setData(
                [
                    "id": doc.documentID,
                    "userId": doc.documentID,
                    "isLocked": false,
                    "submittedAt": FieldValue.delete(),
                ],
                forDocument: submissionRef,
                merge: true
            )
        }
        try await batch.commit()

        allPicks = allPicks.map { pick in
            var unlocked = pick
            unlocked.isLocked = false
            unlocked.submittedAt = nil
            return unlocked
        }
        if var own = userPick {
            own.isLocked = false
            own.submittedAt = nil
            userPick = own
        }
        submissions = submissions.map { sub in
            var unlocked = sub
            unlocked.isLocked = false
            unlocked.submittedAt = nil
            return unlocked
        }
    }

    func updateGameSpread(
        groupId: String,
        weekId: String,
        game: SlateGame,
        spread: Double,
        spreadTeamId: String
    ) async throws {
        let weekRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
        let gamesRef = weekRef.collection("games")
        let patch: [String: Any] = [
            "spread": spread,
            "spreadTeamId": spreadTeamId
        ]

        var wroteGame = false
        if let gameRef = try await existingGameDocument(in: gamesRef, game: game) {
            try await gameRef.updateData(patch)
            wroteGame = true
        }

        let nomSnap = try await weekRef.collection("nominations")
            .whereField("espnEventId", isEqualTo: game.espnEventId)
            .getDocuments()
        var wroteNomination = false
        for doc in nomSnap.documents {
            try await doc.reference.updateData(patch)
            wroteNomination = true
        }

        for index in nominations.indices where nominations[index].espnEventId == game.espnEventId {
            nominations[index].spread = spread
            nominations[index].spreadTeamId = spreadTeamId
        }
        if let index = slateGames.firstIndex(where: {
            $0.id == game.id || $0.espnEventId == game.espnEventId
        }) {
            slateGames[index].spread = spread
            slateGames[index].spreadTeamId = spreadTeamId
        }

        guard wroteGame || wroteNomination else {
            throw PickError.slateGameNotFound
        }
    }

    /// Resolves the live game document. Never creates a new doc.
    private func existingGameDocument(
        in gamesRef: CollectionReference,
        game: SlateGame
    ) async throws -> DocumentReference? {
        var seen = Set<String>()
        for candidate in [game.id, game.espnEventId] where seen.insert(candidate).inserted && !candidate.isEmpty {
            let snap = try await gamesRef.document(candidate).getDocument()
            if snap.exists { return snap.reference }
        }
        let query = try await gamesRef
            .whereField("espnEventId", isEqualTo: game.espnEventId)
            .limit(to: 1)
            .getDocuments()
        return query.documents.first?.reference
    }

    func bulkImportGames(
        groupId: String,
        weekId: String,
        games: [SlateGame],
        rules: GroupRules,
        week: WeekSummary
    ) async throws {
        let slateSize = week.slateSize > 0 ? week.slateSize : rules.slateSize
        let gamesRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .collection("games")
        let existingSnap = try await gamesRef.getDocuments()
        let existing = existingSnap.documents.compactMap { doc in
            SlateGame.fromDocument(id: doc.documentID, data: doc.data())
        }
        let existingIds = Set(existing.map(\.espnEventId) + existingSnap.documents.map(\.documentID))
        let remaining = slateSize - existingSnap.documents.count
        guard remaining > 0 else { throw PickError.slateFull }

        var added: [SlateGame] = []
        for game in games {
            guard added.count < remaining else { break }
            guard !existingIds.contains(game.espnEventId) else { continue }
            guard !added.contains(where: { $0.espnEventId == game.espnEventId }) else { continue }
            try await gamesRef.document(game.id).setData(from: game)
            added.append(game)
        }
    }

    func loadWeekHistory(groupId: String, weekId: String, userId: String) async throws -> WeekHistoryEntry? {
        let weekRef = db.collection("groups").document(groupId).collection("weeks").document(weekId)
        let weekDoc = try await weekRef.getDocument()
        guard let week = try? weekDoc.data(as: WeekSummary.self) else { return nil }

        let gamesSnap = try await weekRef.collection("games").getDocuments()
        let games = gamesSnap.documents.compactMap { doc in
            SlateGame.fromDocument(id: doc.documentID, data: doc.data())
        }

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
        case selectionClosed
        case pickemsNotOpen
        case slateGameNotFound

        var errorDescription: String? {
            switch self {
            case .duplicateGame: return "This game has already been selected."
            case .nominationLimitReached: return "You've reached your Selection limit or the Selection deadline has passed."
            case .slateFull: return "The slate is full — or there are no games to open yet."
            case .deadlinePassed: return "The Pickems deadline has passed."
            case .incompletePicks: return "Please pick every game before submitting your Pickems."
            case .unauthorized: return "You can't remove this Selection."
            case .cannotModifyLockedSlate: return "The slate is locked — games can't be removed."
            case .selectionClosed: return "Selections can't be changed after the Selection deadline."
            case .pickemsNotOpen: return "Pickems open when every Selection is in or the Selection deadline passes. Your commissioner can lock early."
            case .slateGameNotFound: return "Couldn't find that game to update the spread. Pull to refresh and try again."
            }
        }
    }
}
