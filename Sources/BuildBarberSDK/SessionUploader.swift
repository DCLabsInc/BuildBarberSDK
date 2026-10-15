import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Uploads the session recording as multipart/form-data in a field named `video`.
struct SessionUploader: Sendable {
    let apiKey: String
    let endpoint: URL
    var session: URLSession = .shared

    func makeUploadRequest(videoURL: URL) throws -> (request: URLRequest, body: Data) {
        var form = MultipartFormData()
        let data = try Data(contentsOf: videoURL, options: .mappedIfSafe)
        form.addField(name: "video", value: data, filename: videoURL.lastPathComponent, mimeType: "video/mp4")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return (request, form.finalized())
    }

    func upload(videoURL: URL) async throws {
        let (request, body) = try makeUploadRequest(videoURL: videoURL)
        let (data, response) = try await session.upload(for: request, from: body)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Self.error(statusCode: http.statusCode, responseBody: data)
        }
    }

    static func error(statusCode: Int, responseBody: Data) -> BuildBarberError {
        BuildBarberError.make(statusCode: statusCode, responseBody: responseBody)
    }
}
