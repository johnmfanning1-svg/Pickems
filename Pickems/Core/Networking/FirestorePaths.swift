import FirebaseFirestore

enum FirestoreCollection {
    static let users = "users"
    static let handles = "handles"
    static let groups = "groups"
    static let inviteCodes = "inviteCodes"
    static let weeks = "weeks"
    static let nominations = "nominations"
    static let games = "games"
    static let picks = "picks"
    static let submissions = "submissions"
    static let members = "members"
    static let standings = "standings"
    static let seasons = "seasons"
    static let career = "career"
}

enum FirestoreDocument {
    static let currentStandings = "current"
}

enum FirestoreField {
    static let memberIds = "memberIds"
    static let fcmToken = "fcmToken"
    static let groupId = "groupId"
    static let nominationCount = "nominationCount"
    static let spread = "spread"
    static let spreadTeamId = "spreadTeamId"
}

extension Firestore {
    func group(_ groupId: String) -> DocumentReference {
        collection(FirestoreCollection.groups).document(groupId)
    }

    func week(groupId: String, weekId: String) -> DocumentReference {
        group(groupId).collection(FirestoreCollection.weeks).document(weekId)
    }

    func user(_ userId: String) -> DocumentReference {
        collection(FirestoreCollection.users).document(userId)
    }

    func inviteCode(_ code: String) -> DocumentReference {
        collection(FirestoreCollection.inviteCodes).document(code)
    }

    func handle(_ key: String) -> DocumentReference {
        collection(FirestoreCollection.handles).document(key)
    }
}

extension DocumentReference {
    var weeks: CollectionReference { collection(FirestoreCollection.weeks) }
    var members: CollectionReference { collection(FirestoreCollection.members) }
    var standings: CollectionReference { collection(FirestoreCollection.standings) }
    var seasons: CollectionReference { collection(FirestoreCollection.seasons) }
    var career: CollectionReference { collection(FirestoreCollection.career) }
}

extension DocumentReference {
    var nominations: CollectionReference { collection(FirestoreCollection.nominations) }
    var games: CollectionReference { collection(FirestoreCollection.games) }
    var picks: CollectionReference { collection(FirestoreCollection.picks) }
}
