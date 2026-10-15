import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Uploads the session payload and video as multipart/form-data.
struct SessionUploader: Sendable {
    let apiKey: String
    let endpoint: URL
    var session: URLSession = .shared

    func makeUploadRequest<Payload: Encodable>(
        payload: Payload,
        videoURL: URL?
    ) throws -> (request: URLRequest, body: Data) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var form = MultipartFormData()
        form.addField(name: "payload", value: try encoder.encode(payload),
                      mimeType: "application/json")
        if let videoURL {
            let data = try Data(contentsOf: videoURL, options: .mappedIfSafe)
            form.addField(name: "video", value: data, filename: videoURL.lastPathComponent, mimeType: "video/mp4")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return (request, form.finalized())
    }

    func upload<Payload: Encodable>(payload: Payload, videoURL: URL?) async throws {
        let (request, body) = try makeUploadRequest(payload: payload, videoURL: videoURL)
        let (data, response) = try await session.upload(for: request, from: body)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Self.error(statusCode: http.statusCode, responseBody: data)
        }
    }

    static func error(statusCode: Int, responseBody: Data) -> BuildBarberError {
        BuildBarberError.make(statusCode: statusCode, responseBody: responseBody)
    }
}
