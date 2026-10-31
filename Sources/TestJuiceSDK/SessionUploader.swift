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
        try makeUploadRequest(fileURL: videoURL, field: "video", mimeType: "video/mp4")
    }

    func makeUploadRequest(fileURL: URL, field: String, mimeType: String) throws -> (request: URLRequest, body: Data) {
        var form = MultipartFormData()
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        form.addField(name: field, value: data, filename: fileURL.lastPathComponent, mimeType: mimeType)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return (request, form.finalized())
    }

    func upload(videoURL: URL) async throws {
        try await upload(fileURL: videoURL, field: "video", mimeType: "video/mp4")
    }

    func upload(fileURL: URL, field: String, mimeType: String) async throws {
        let (request, body) = try makeUploadRequest(fileURL: fileURL, field: field, mimeType: mimeType)
        let (data, response) = try await session.upload(for: request, from: body)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Self.error(statusCode: http.statusCode, responseBody: data)
        }
    }

    static func error(statusCode: Int, responseBody: Data) -> TestJuiceError {
        TestJuiceError.make(statusCode: statusCode, responseBody: responseBody)
    }
}
