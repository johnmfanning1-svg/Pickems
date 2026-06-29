import Foundation
import FirebaseStorage
import UIKit

@MainActor
enum AvatarService {
    static func uploadAvatar(userId: String, image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.75) else {
            throw AvatarError.invalidImage
        }

        let ref = Storage.storage().reference().child("avatars/\(userId).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    enum AvatarError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "Could not process the selected photo." }
    }
}
