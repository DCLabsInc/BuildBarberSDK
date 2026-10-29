import Testing
import Foundation
@testable import BuildBarberSDK

@Suite struct AppleSignInEmailTests {
    @Test func credentialEmailTakesPrecedence() {
        #expect(AppleSignInEmail.resolve(credentialEmail: "tester@example.com", identityToken: nil)
            == "tester@example.com")
    }

    @Test func extractsEmailFromIdentityToken() throws {
        let payload = Data(#"{"email":"tester@example.com"}"#.utf8)
        let encodedPayload = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = Data("header.\(encodedPayload).signature".utf8)

        #expect(AppleSignInEmail.resolve(credentialEmail: nil, identityToken: token)
            == "tester@example.com")
    }

    @Test(arguments: [
        Data("not-a-token".utf8),
        Data("header.%%% .signature".utf8),
        Data("header.e30.signature".utf8)
    ])
    func missingOrMalformedEmailReturnsNil(identityToken: Data) {
        #expect(AppleSignInEmail.resolve(credentialEmail: nil, identityToken: identityToken) == nil)
    }
}

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
    @Test func uploadRequestIncludesVideoFieldAndAPIKey() throws {
        let videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("buildbarber-test-\(UUID().uuidString).mp4")
        try Data("video-data".utf8).write(to: videoURL)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let uploader = SessionUploader(
            apiKey: "test-key",
            endpoint: URL(string: "https://portal.buildbarber.com/api/sdk/v1/tests/7/video")!)
        let (request, body) = try uploader.makeUploadRequest(videoURL: videoURL)

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
        #expect(body.range(of: Data("name=\"video\"; filename=\"\(videoURL.lastPathComponent)\"".utf8)) != nil)
        #expect(body.range(of: Data("name=\"payload\"".utf8)) == nil)
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

    @Test func resultWithoutVideoUsesJSONRequest() throws {
        let client = BuildBarberClient(configuration: .init(apiKey: "k123"))
        let result = BuildBarberTestResult(
            testType: .feature,
            codeword: "code",
            testerEmail: "tester@example.com",
            outcome: nil,
            feedback: "Feedback",
            checkedItems: [])

        let request = try client.makeResultRequest(result)

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://portal.buildbarber.com/api/sdk/v1/tests/results")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "k123")
        #expect(request.httpBody?.range(of: Data(#""feedback":"Feedback""#.utf8)) != nil)
    }

    @Test func videoEndpointUsesTestRecordId() throws {
        let client = BuildBarberClient(configuration: .init(apiKey: "k123"))
        #expect(try client.makeVideoRequestURL(testRecordId: 42).absoluteString
            == "https://portal.buildbarber.com/api/sdk/v1/tests/42/video")
        let response = try JSONDecoder().decode(
            BuildBarberClient.TestResultResponse.self,
            from: Data(#"{"testRecordId":42,"status":"passed"}"#.utf8))
        #expect(response.testRecordId == 42)
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

    @Test func emptyTesterEmailUsesAnonymousAddress() throws {
        let result = BuildBarberTestResult(
            testType: .feature,
            codeword: "code",
            testerEmail: "  \n",
            outcome: nil,
            feedback: "Feedback",
            checkedItems: [])
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        #expect(json["testerEmail"] as? String == "anonymous@nowhere.com")
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

@Suite struct RecordingLimitsTests {
    @Test func maxDurationKeepsExpectedSizeUnderUploadLimit() {
        let bitsPerSecond = Double(RecordingLimits.videoBitRate + RecordingLimits.audioBitRate)
        let expectedBytes = RecordingLimits.maxDuration * bitsPerSecond / 8
        #expect(expectedBytes < Double(RecordingLimits.maxUploadBytes))
        #expect(RecordingLimits.maxDuration > 60)
    }

    @Test func uploadLimitIsExclusiveOfExactLimit() {
        #expect(!RecordingLimits.exceedsUploadLimit(fileSize: RecordingLimits.maxUploadBytes))
        #expect(RecordingLimits.exceedsUploadLimit(fileSize: RecordingLimits.maxUploadBytes + 1))
    }
}

@Suite struct TestDefinitionTests {
    @Test func definitionRequestTargetsTestsEndpoint() throws {
        let client = BuildBarberClient(configuration: BuildBarberConfiguration(apiKey: "k"))
        let request = try client.makeDefinitionRequest(testType: .release, codeword: "a b&c")
        let url = try #require(request.url?.absoluteString)
        #expect(url.hasSuffix("/api/sdk/v1/tests?testType=Release&codeword=a%20b%26c"))
        #expect(request.httpMethod == "GET")
    }

    @Test func decodesShowPassFailFlag() throws {
        let json = #"{"testType":"Feature","codeword":"x","showPassFailButtons":false,"checklist":[]}"#
        let decoded = try JSONDecoder().decode(BuildBarberClient.TestDefinitionResponse.self, from: Data(json.utf8))
        #expect(decoded.showPassFailButtons == false)
    }

    @Test func decodesRewardFromDefinition() throws {
        let json = #"{"showPassFailButtons":true,"reward":{"description":"Free coffee","groupTitle":"Perks"}}"#
        let decoded = try JSONDecoder().decode(BuildBarberClient.TestDefinitionResponse.self, from: Data(json.utf8))
        #expect(decoded.reward?.description == "Free coffee")
        #expect(decoded.reward?.groupTitle == "Perks")
    }

    @Test(arguments: [
        #"{"showPassFailButtons":false}"#,
        #"{"showPassFailButtons":false,"reward":null}"#
    ])
    func missingOrNullRewardIsAccepted(json: String) throws {
        let decoded = try JSONDecoder().decode(BuildBarberClient.TestDefinitionResponse.self, from: Data(json.utf8))
        #expect(decoded.reward == nil)
    }

    @Test func testModelDecodesReward() throws {
        let json = #"{"title":"Test","instructions":"Try it.","checklist":[],"showPassFailButtons":false,"reward":{"description":null,"groupTitle":"Prize"}}"#
        let decoded = try JSONDecoder().decode(BuildBarberTest.self, from: Data(json.utf8))
        #expect(decoded.reward?.description == "Prize")
        #expect(decoded.reward?.groupTitle == "Prize")
    }
}
