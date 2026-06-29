import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
@Observable
final class GroupService {
    var groups: [PickemGroup] = []
    var selectedGroup: PickemGroup?
    var members: [GroupMember] = []
    var standings: GroupStandings?
    var currentWeek: WeekSummary?
    var cfbWeek: CFBWeekInfo?
    var isLoading = false
    var errorMessage: String?

    private let db = Firestore.firestore()
    private var groupListener: ListenerRegistration?
    private var weekListener: ListenerRegistration?
    private var standingsListener: ListenerRegistration?
    private var observedWeekId: String?

    func loadGroups(for userId: String) {
        groupListener?.remove()
        groupListener = db.collection("groups")
            .whereField("memberIds", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error {
                        self?.errorMessage = error.localizedDescription
                        return
                    }
                    self?.groups = snapshot?.documents.compactMap { doc in
                        try? doc.data(as: PickemGroup.self)
                    } ?? []
                    Task { @MainActor in
                        await self?.backfillInviteCodeIndexes(for: userId)
                    }
                    if self?.selectedGroup == nil {
                        self?.selectedGroup = self?.groups.first
                    }
                    if let groupId = self?.selectedGroup?.id {
                        await self?.syncCurrentWeekFromESPN(groupId: groupId)
                    }
                }
            }
    }

    func selectGroup(_ group: PickemGroup) {
        selectedGroup = group
        Task {
            await syncCurrentWeekFromESPN(groupId: group.id)
        }
    }

    func syncCurrentWeekFromESPN(groupId: String) async {
        let rules = selectedGroup?.rules ?? .default
        let weekInfo: CFBWeekInfo
        do {
            weekInfo = try await ESPNService.shared.currentWeek()
        } catch {
            errorMessage = error.localizedDescription
            if observedWeekId == nil {
                observeGroupDetails(groupId: groupId, weekId: CFBWeekSync.fallbackWeekId())
            }
            return
        }

        let weekId = CFBWeekSync.weekId(for: weekInfo)
        let weekChanged = cfbWeek?.weekNumber != weekInfo.weekNumber
            || cfbWeek?.seasonYear != weekInfo.seasonYear
            || observedWeekId != weekId

        cfbWeek = weekInfo

        guard weekChanged || currentWeek == nil else { return }

        isLoading = currentWeek == nil
        defer { isLoading = false }

        let weekRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)

        do {
            let snapshot = try await weekRef.getDocument()
            if !snapshot.exists {
                let week = CFBWeekSync.makeWeekSummary(id: weekId, info: weekInfo, rules: rules)
                try await weekRef.setData(from: week)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        observeGroupDetails(groupId: groupId, weekId: weekId)
    }

    func createGroup(name: String, commissionerId: String, displayName: String) async throws -> PickemGroup {
        let inviteCode = generateInviteCode()
        let groupRef = db.collection("groups").document()
        let group = PickemGroup(
            id: groupRef.documentID,
            name: name,
            inviteCode: inviteCode,
            commissionerId: commissionerId,
            memberIds: [commissionerId],
            rules: .default,
            createdAt: Date()
        )
        try await groupRef.setData(from: group)
        try await db.collection("inviteCodes").document(inviteCode).setData(["groupId": groupRef.documentID])

        let member = GroupMember(
            id: commissionerId,
            displayName: displayName,
            avatarColorHex: AvatarColors.randomHex(),
            role: .commissioner,
            joinedAt: Date(),
            seasonWins: 0,
            seasonLosses: 0
        )
        try await groupRef.collection("members").document(commissionerId).setData(from: member)
        selectedGroup = group
        if !groups.contains(where: { $0.id == group.id }) {
            groups.append(group)
        }
        await syncCurrentWeekFromESPN(groupId: group.id)
        return group
    }

    func joinGroup(inviteCode: String, userId: String, displayName: String, avatarColorHex: String) async throws {
        let normalizedCode = inviteCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let codeDoc = try await db.collection("inviteCodes").document(normalizedCode).getDocument()
        guard codeDoc.exists, let groupId = codeDoc.data()?["groupId"] as? String else {
            throw GroupError.invalidInviteCode
        }

        let doc = try await db.collection("groups").document(groupId).getDocument()
        guard doc.exists else {
            throw GroupError.invalidInviteCode
        }

        var group = try doc.data(as: PickemGroup.self)
        guard !group.memberIds.contains(userId) else {
            selectedGroup = group
            await syncCurrentWeekFromESPN(groupId: group.id)
            return
        }

        group.memberIds.append(userId)
        try await doc.reference.updateData(["memberIds": group.memberIds])

        let member = GroupMember(
            id: userId,
            displayName: displayName,
            avatarColorHex: avatarColorHex,
            role: .member,
            joinedAt: Date(),
            seasonWins: 0,
            seasonLosses: 0
        )
        try await doc.reference.collection("members").document(userId).setData(from: member)
        selectedGroup = group
        await syncCurrentWeekFromESPN(groupId: group.id)
    }

    func leaveGroup(groupId: String, userId: String) async throws {
        guard let group = groups.first(where: { $0.id == groupId }) else {
            throw GroupError.groupNotFound
        }
        guard group.memberIds.contains(userId) else { return }

        if group.commissionerId == userId {
            if group.memberIds.count == 1 {
                try await deleteGroup(groupId: groupId)
                return
            }
            guard let successor = group.memberIds.first(where: { $0 != userId }) else {
                throw GroupError.cannotLeaveAsSoleCommissioner
            }
            try await transferCommissioner(groupId: groupId, toUserId: successor)
        }

        var updatedIds = group.memberIds.filter { $0 != userId }
        try await db.collection("groups").document(groupId).updateData(["memberIds": updatedIds])
        try await db.collection("groups").document(groupId)
            .collection("members").document(userId).delete()

        groups.removeAll { $0.id == groupId }
        if selectedGroup?.id == groupId {
            selectedGroup = groups.first
            if let next = selectedGroup {
                await syncCurrentWeekFromESPN(groupId: next.id)
            } else {
                currentWeek = nil
                standings = nil
                members = []
            }
        }
    }

    func deleteGroup(groupId: String) async throws {
        guard let group = groups.first(where: { $0.id == groupId }) else {
            throw GroupError.groupNotFound
        }
        guard group.commissionerId == Auth.auth().currentUser?.uid else {
            throw GroupError.notCommissioner
        }

        let groupRef = db.collection("groups").document(groupId)
        let weeks = try await groupRef.collection("weeks").getDocuments()
        for week in weeks.documents {
            try await deleteWeekData(groupRef: groupRef, weekId: week.documentID)
        }
        let members = try await groupRef.collection("members").getDocuments()
        for member in members.documents {
            try await member.reference.delete()
        }
        try await groupRef.collection("standings").document("current").delete()
        try await db.collection("inviteCodes").document(group.inviteCode).delete()
        try await groupRef.delete()

        groups.removeAll { $0.id == groupId }
        if selectedGroup?.id == groupId {
            selectedGroup = groups.first
            currentWeek = nil
            standings = nil
            self.members = []
        }
    }

    func transferCommissioner(groupId: String, toUserId: String) async throws {
        guard let group = groups.first(where: { $0.id == groupId }) else {
            throw GroupError.groupNotFound
        }
        let previousCommissionerId = group.commissionerId

        try await db.collection("groups").document(groupId).updateData(["commissionerId": toUserId])
        try await db.collection("groups").document(groupId)
            .collection("members").document(toUserId)
            .updateData(["role": GroupMember.MemberRole.commissioner.rawValue])
        if previousCommissionerId != toUserId {
            try await db.collection("groups").document(groupId)
                .collection("members").document(previousCommissionerId)
                .updateData(["role": GroupMember.MemberRole.member.rawValue])
        }
        if var group = groups.first(where: { $0.id == groupId }) {
            group.commissionerId = toUserId
            if let idx = groups.firstIndex(where: { $0.id == groupId }) {
                groups[idx] = group
            }
            if selectedGroup?.id == groupId {
                selectedGroup = group
            }
        }
    }

    func fetchPastWeeks(groupId: String, limit: Int = 16) async throws -> [WeekSummary] {
        let snapshot = try await db.collection("groups").document(groupId)
            .collection("weeks")
            .order(by: "weekNumber", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: WeekSummary.self) }
    }

    func loadPlayerSeasonStats(groupId: String, userId: String) async throws -> PlayerSeasonStats {
        let weeks = try await fetchPastWeeks(groupId: groupId, limit: 20)
        var weeklyRecords: [WeeklyRecord] = []
        var seasonWins = 0
        var seasonLosses = 0
        var bestWeek: WeeklyRecord?

        for week in weeks where week.status == .scored {
            let pickSnap = try await db.collection("groups").document(groupId)
                .collection("weeks").document(week.id)
                .collection("picks").document(userId).getDocument()
            let gamesSnap = try await db.collection("groups").document(groupId)
                .collection("weeks").document(week.id)
                .collection("games").getDocuments()
            let games = gamesSnap.documents.compactMap { try? $0.data(as: SlateGame.self) }
            guard let pick = try? pickSnap.data(as: UserPick.self) else { continue }

            var wins = 0
            var losses = 0
            for game in games where game.status == .final {
                guard let pickedId = pick.picks[game.id] else { continue }
                if let correct = ScoringEngine.isPickCorrect(pickedTeamId: pickedId, game: game) {
                    if correct { wins += 1 } else { losses += 1 }
                }
            }
            let record = WeeklyRecord(week: week.weekNumber, wins: wins, losses: losses)
            weeklyRecords.append(record)
            seasonWins += wins
            seasonLosses += losses
            if bestWeek == nil || wins > (bestWeek?.wins ?? 0) {
                bestWeek = record
            }
        }

        weeklyRecords.sort { $0.week < $1.week }
        let streak = computeStreak(from: weeklyRecords)

        let member = members.first(where: { $0.id == userId })
        return PlayerSeasonStats(
            id: userId,
            displayName: member?.displayName ?? "Player",
            weeklyRecords: weeklyRecords,
            seasonWins: member?.seasonWins ?? seasonWins,
            seasonLosses: member?.seasonLosses ?? seasonLosses,
            currentStreak: streak,
            bestWeekNumber: bestWeek?.week,
            bestWeekWins: bestWeek?.wins,
            bestWeekLosses: bestWeek?.losses
        )
    }

    private func computeStreak(from records: [WeeklyRecord]) -> Int {
        var streak = 0
        for record in records.reversed() {
            if record.wins > record.losses {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    private func deleteWeekData(groupRef: DocumentReference, weekId: String) async throws {
        let weekRef = groupRef.collection("weeks").document(weekId)
        for sub in ["nominations", "games", "picks", "submissions"] {
            let snap = try await weekRef.collection(sub).getDocuments()
            for doc in snap.documents {
                try await doc.reference.delete()
            }
        }
        try await weekRef.delete()
    }

    func updateRules(groupId: String, rules: GroupRules) async throws {
        try await db.collection("groups").document(groupId).updateData([
            "rules": try Firestore.Encoder().encode(rules)
        ])
        selectedGroup?.rules = rules
    }

    func lockSlateEarly(groupId: String, weekId: String, rules: GroupRules, kickoffs: [Date]) async throws {
        let updates = WeekTransition.lockEarlyUpdates(rules: rules, kickoffs: kickoffs)
        try await db.week(groupId: groupId, weekId: weekId).updateData(updates)
    }

    func resolveTie(groupId: String, standingUserId: String) async throws {
        guard var standings else { return }
        guard let index = standings.entries.firstIndex(where: { $0.id == standingUserId }) else { return }

        let tiedRank = standings.entries[index].rank
        standings.entries[index].isTied = false

        for i in standings.entries.indices where i != index {
            if standings.entries[i].rank == tiedRank && standings.entries[i].isTied {
                standings.entries[i].rank = tiedRank + 1
            }
        }

        standings.entries = ScoringEngine.rankedStandings(
            entries: standings.entries,
            weekly: true,
            tieBreaker: selectedGroup?.rules.tieBreaker ?? .commissionerOverride
        )
        try await db.collection("groups").document(groupId)
            .collection("standings").document("current")
            .setData(from: standings)
    }

    private func observeGroupDetails(groupId: String, weekId: String) {
        weekListener?.remove()
        standingsListener?.remove()
        observedWeekId = weekId

        weekListener = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    self?.currentWeek = try? snapshot?.data(as: WeekSummary.self)
                }
            }

        standingsListener = db.collection("groups").document(groupId)
            .collection("standings").document("current")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    self?.standings = try? snapshot?.data(as: GroupStandings.self)
                }
            }

        Task {
            let membersSnapshot = try await db.collection("groups").document(groupId)
                .collection("members").getDocuments()
            members = membersSnapshot.documents.compactMap { try? $0.data(as: GroupMember.self) }
        }
    }

    private func backfillInviteCodeIndexes(for userId: String) async {
        for group in groups where group.commissionerId == userId {
            let ref = db.collection("inviteCodes").document(group.inviteCode)
            do {
                let doc = try await ref.getDocument()
                if !doc.exists {
                    try await ref.setData(["groupId": group.id])
                }
            } catch {
                // Non-fatal — join still works once indexed.
            }
        }
    }

    private func generateInviteCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement() ?? "A" })
    }

    enum GroupError: LocalizedError {
        case invalidInviteCode
        case groupNotFound
        case notCommissioner
        case cannotLeaveAsSoleCommissioner

        var errorDescription: String? {
            switch self {
            case .invalidInviteCode: return "Invalid invite code. Check with your commissioner."
            case .groupNotFound: return "Group not found."
            case .notCommissioner: return "Only the commissioner can delete this group."
            case .cannotLeaveAsSoleCommissioner: return "Transfer commissioner role or delete the group before leaving."
            }
        }
    }
}
