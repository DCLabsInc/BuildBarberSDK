import Testing
import Foundation
@testable import BuildBarberSDK

@Suite struct PayloadTests {
    @Test func multipartContainsPartsAndTerminator() {
        var form = MultipartFormData(boundary: "B")
        form.addField(name: "metadata", value: Data("{}".utf8), mimeType: "application/json")
        form.addField(name: "video", value: Data([1, 2]), filename: "a.mp4", mimeType: "video/mp4")
        let text = String(decoding: form.finalized(), as: UTF8.self)
        #expect(text.contains("name=\"metadata\""))
        #expect(text.contains("filename=\"a.mp4\""))
        #expect(text.hasSuffix("--B--\r\n"))
        #expect(form.contentType == "multipart/form-data; boundary=B")
    }
}

@Suite struct SessionUploaderTests {
    @Test func uploadRequestIncludesResultVideoAndAPIKey() throws {
        let videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("buildbarber-test-\(UUID().uuidString).mp4")
        try Data("video-data".utf8).write(to: videoURL)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let uploader = SessionUploader(
            apiKey: "test-key",
            endpoint: URL(string: "https://portal.buildbarber.com/api/sdk/v1/tests/results")!)
        let result = BuildBarberTestResult(
            testType: .feature,
            codeword: "code",
            testerEmail: "tester@example.com",
            outcome: "pass",
            feedback: "Looks good",
            checkedItems: ["check-1"])
        let (request, body) = try uploader.makeUploadRequest(payload: result, videoURL: videoURL)

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
        #expect(body.range(of: Data(#""testerEmail":"tester@example.com""#.utf8)) != nil)
        #expect(body.range(of: Data("name=\"payload\"".utf8)) != nil)
        #expect(body.range(of: Data("filename=\"payload.json\"".utf8)) == nil)
        #expect(body.range(of: Data("filename=\"\(videoURL.lastPathComponent)\"".utf8)) != nil)
        #expect(body.range(of: Data("video-data".utf8)) != nil)
    }

    @Test func uploadErrorsIncludeAPIResponseMessage() {
        let error = SessionUploader.error(
            statusCode: 400,
            responseBody: Data(#"{"error":"invalid_result","message":"Missing codeword."}"#.utf8))
        #expect(error.localizedDescription == "Missing codeword.")
    }
}

@Suite struct ClientTests {
    @Test func requestUsesPortalHostPathAndApiKey() throws {
        let client = BuildBarberClient(configuration: .init(apiKey: "k123"))
        let req = try client.makeRequest(method: "GET", path: "/tests?limit=5")
        #expect(req.url?.absoluteString == "https://portal.buildbarber.com/api/sdk/v1/tests?limit=5")
        #expect(req.value(forHTTPHeaderField: "X-Api-Key") == "k123")
    }

    @Test func feedbackOnlyResultOmitsOutcome() throws {
        let result = BuildBarberTestResult(
            testType: .release,
            codeword: "code",
            testerEmail: "tester@example.com",
            outcome: nil,
            feedback: "Feedback",
            checkedItems: ["check-1"])
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        #expect(json["testType"] as? String == "Release")
        #expect(json["checkedItems"] as? [String] == ["check-1"])
        #expect(json["outcome"] == nil)
    }

    @Test func errorBodyDecodes() throws {
        let body = try JSONDecoder().decode(APIErrorBody.self, from: Data(#"{"error":"bad_key","message":"nope"}"#.utf8))
        #expect(body.error == "bad_key")
    }

    @Test func requestErrorsExposeActionableMessages() {
        #expect(BuildBarberError.api(
            status: 400,
            body: APIErrorBody(error: "invalid_result", message: "Missing codeword.")
        ).localizedDescription == "Missing codeword.")
        #expect(BuildBarberError.badStatus(500).localizedDescription == "The request failed (HTTP 500).")
    }
}
