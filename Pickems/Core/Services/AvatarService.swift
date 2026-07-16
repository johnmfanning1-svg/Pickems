import Foundation
import FirebaseStorage
import UIKit

@MainActor
enum AvatarService {
    static func uploadAvatar(userId: String, image: UIImage) async throws -> String {
        guard let data = ImageResizer.resizedJPEGData(from: image) else {
            throw AvatarError.invalidImage
        }

        let ref = Storage.storage().reference().child("avatars/\(userId).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            _ = try await ref.putDataAsync(data, metadata: metadata)
            let url = try await ref.downloadURL()
            return url.absoluteString
        } catch {
            CrashReport.record(error, code: "avatar_upload_failed", metadata: [
                "uid": AppEvents.shortUID(userId),
            ])
            throw error
        }
    }

    static func deleteAvatar(userId: String) async throws {
        let ref = Storage.storage().reference().child("avatars/\(userId).jpg")
        do {
            try await ref.delete()
        } catch {
            let nsError = error as NSError
            // Already gone is fine during account deletion.
            if nsError.domain == StorageErrorDomain,
               nsError.code == StorageErrorCode.objectNotFound.rawValue {
                return
            }
            throw error
        }
    }

    enum AvatarError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "Could not process the selected photo." }
    }
}
