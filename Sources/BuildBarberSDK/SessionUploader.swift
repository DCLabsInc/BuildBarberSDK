import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum UploadError: Error, Sendable {
    case badStatus(Int)
}

/// Uploads the session payload and video as multipart/form-data.
struct SessionUploader: Sendable {
    let apiKey: String
    let endpoint: URL
    var session: URLSession = .shared

    func upload(payload: SessionPayload, videoURL: URL?) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var form = MultipartFormData()
        form.addField(name: "payload", value: try encoder.encode(payload),
                      filename: "payload.json", mimeType: "application/json")
        if let videoURL {
            // Mapped read avoids loading the whole recording into memory eagerly.
            let data = try Data(contentsOf: videoURL, options: .mappedIfSafe)
            form.addField(name: "video", value: data, filename: videoURL.lastPathComponent, mimeType: "video/mp4")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.upload(for: request, from: form.finalized())
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UploadError.badStatus(http.statusCode)
        }
    }
}
