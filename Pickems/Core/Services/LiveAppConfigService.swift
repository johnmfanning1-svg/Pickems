import Foundation
import FirebaseFirestore

/// Pure rules for `appConfig/live.minimumBuild`. Fail open when the field is
/// missing, zero, or unreadable so a bad config cannot brick the app.
enum ForceUpdatePolicy {
    static var currentBuildNumber: Int {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return Int(raw) ?? 0
    }

    static func parseMinimumBuild(_ raw: Any?) -> Int? {
        switch raw {
        case nil, is NSNull:
            return nil
        case let value as Int:
            return value > 0 ? value : nil
        case let value as Int64:
            return value > 0 ? Int(value) : nil
        case let value as Double:
            return value > 0 ? Int(value) : nil
        case let value as NSNumber:
            return value.intValue > 0 ? value.intValue : nil
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = Int(trimmed), parsed > 0 else { return nil }
            return parsed
        default:
            return nil
        }
    }

    static func requiresUpdate(currentBuild: Int, minimumBuild: Int?) -> Bool {
        guard let minimumBuild else { return false }
        return currentBuild < minimumBuild
    }
}

/// Listens to `appConfig/live` so a portal `minimumBuild` bump can block older binaries.
@MainActor
@Observable
final class LiveAppConfigService {
    private(set) var minimumBuild: Int?
    @ObservationIgnored
    private var listener: ListenerRegistration?

    var requiresUpdate: Bool {
        ForceUpdatePolicy.requiresUpdate(
            currentBuild: ForceUpdatePolicy.currentBuildNumber,
            minimumBuild: minimumBuild
        )
    }

    func start() {
        guard listener == nil else { return }
        listener = Firestore.firestore().liveAppConfig.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                self?.apply(snapshot: snapshot, error: error)
            }
        }
    }

    func apply(snapshot: DocumentSnapshot?, error: Error?) {
        if let error {
            AppLog.notice(AppLog.firestore, "appConfig/live unreadable — force update stays off", metadata: [
                "error": AppLog.describe(error),
            ])
            return
        }
        guard let data = snapshot?.data() else { return }
        minimumBuild = ForceUpdatePolicy.parseMinimumBuild(data[FirestoreField.minimumBuild])
    }
}
