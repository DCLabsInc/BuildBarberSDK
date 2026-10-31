import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Configuration for talking to the TestJuice REST API.
public struct TestJuiceConfiguration: Sendable {
    /// Use the portal host: testjuice.com redirects to it, which breaks POST requests.
    public static let defaultBaseURL = URL(string: "https://portal.testjuice.com")!

    /// "iOS SDK API key" generated in TestJuice Settings.
    public var apiKey: String
    public var baseURL: URL

    public init(apiKey: String, baseURL: URL = TestJuiceConfiguration.defaultBaseURL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }
}

public enum TestJuiceTestType: String, Codable, Sendable {
    case feature = "Feature"
    case release = "Release"
}

public struct SdkRewardInfo: Decodable, Sendable {
    public let description: String
    public let groupTitle: String?
    public let availableCodes: Int?
    public let availabilityStatus: String?
    public let totalCodes: Int?

    public var hasNoCodesLeft: Bool { availableCodes == 0 }

    private enum CodingKeys: String, CodingKey { case description, groupTitle, availableCodes, availabilityStatus, totalCodes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let desc = try c.decodeIfPresent(String.self, forKey: .description)
        let group = try c.decodeIfPresent(String.self, forKey: .groupTitle)
        groupTitle = group
        availableCodes = try c.decodeIfPresent(Int.self, forKey: .availableCodes)
        availabilityStatus = try c.decodeIfPresent(String.self, forKey: .availabilityStatus)
        totalCodes = try c.decodeIfPresent(Int.self, forKey: .totalCodes)
        description = (desc?.isEmpty == false ? desc : nil) ?? group ?? ""
    }
}

public struct TestJuiceTest: Decodable, Sendable {
    public struct ChecklistItem: Decodable, Sendable {
        public let key: String
        public let label: String
        public let kind: String
    }

    public let title: String
    public let instructions: String
    public let checklist: [ChecklistItem]
    public let showPassFailButtons: Bool
    public let reward: SdkRewardInfo?
}

public struct TestJuiceTestResult: Encodable, Sendable {
    public let testType: TestJuiceTestType
    public let codeword: String
    public let testerEmail: String
    public let outcome: String?
    public let feedback: String
    public let checkedItems: [String]

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(testType, forKey: .testType)
        try container.encode(codeword, forKey: .codeword)
        try container.encode(
            testerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "anonymous@nowhere.com"
                : testerEmail,
            forKey: .testerEmail)
        try container.encodeIfPresent(outcome, forKey: .outcome)
        try container.encode(feedback, forKey: .feedback)
        try container.encode(checkedItems, forKey: .checkedItems)
        try container.encodeIfPresent(telemetry?.deviceModel, forKey: .deviceModel)
        try container.encodeIfPresent(telemetry?.osVersion, forKey: .osVersion)
        try container.encodeIfPresent(telemetry?.networkType, forKey: .networkType)
        try container.encodeIfPresent(telemetry?.batteryLevel, forKey: .batteryLevel)
        try container.encodeIfPresent(telemetry?.appVersion, forKey: .appVersion)
        try container.encodeIfPresent(telemetry?.localeLanguage, forKey: .localeLanguage)
        try container.encodeIfPresent(telemetry?.deviceMemoryMb, forKey: .deviceMemoryMb)
        try container.encodeIfPresent(telemetry?.screenSize, forKey: .screenSize)
    }

    private enum CodingKeys: String, CodingKey {
        case testType
        case codeword
        case testerEmail
        case outcome
        case feedback
        case checkedItems
        case deviceModel
        case osVersion
        case networkType
        case batteryLevel
        case appVersion
        case localeLanguage
        case deviceMemoryMb
        case screenSize
    }

    var telemetry: TestJuiceDeviceTelemetry? = nil
}

/// Error body returned by the API: `{ "error": "<code>", "message": "<text>" }`.
public struct APIErrorBody: Codable, Sendable, Equatable {
    public let error: String
    public let message: String?
}

public enum TestJuiceError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL
    case api(status: Int, body: APIErrorBody)
    case badStatus(Int)
    case http(status: Int, text: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The request URL is invalid."
        case let .api(status, body):
            body.message ?? "The request failed (HTTP \(status))."
        case let .badStatus(status), let .http(status, _):
            "The request failed (HTTP \(status))."
        }
    }

    var statusCode: Int? {
        switch self {
        case .invalidURL: nil
        case let .api(status, _), let .badStatus(status), let .http(status, _): status
        }
    }

    /// Full error text (status, code and raw response) suitable for copying into a bug report.
    public var detailedDescription: String {
        switch self {
        case .invalidURL:
            return "The request URL is invalid."
        case let .api(status, body):
            return "HTTP \(status)\nerror: \(body.error)\nmessage: \(body.message ?? "none")"
        case let .badStatus(status):
            return "HTTP \(status)"
        case let .http(status, text):
            return "HTTP \(status)\n\(text)"
        }
    }
}

extension TestJuiceError {
    static func make(statusCode: Int, responseBody: Data) -> TestJuiceError {
        if let apiError = try? JSONDecoder().decode(APIErrorBody.self, from: responseBody) {
            return .api(status: statusCode, body: apiError)
        }
        let text = String(decoding: responseBody.prefix(4096), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .badStatus(statusCode) : .http(status: statusCode, text: text)
    }
}

/// Minimal client for `/api/sdk/v1`. JSON is camelCase in both directions.
public struct TestJuiceClient: Sendable {
    public static let apiPath = "/api/sdk/v1"

    public let configuration: TestJuiceConfiguration
    private let session: URLSession

    public init(configuration: TestJuiceConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func makeRequest(method: String, path: String, body: Data? = nil) throws -> URLRequest {
        let trimmed = path.hasPrefix("/") ? path : "/" + path
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw TestJuiceError.invalidURL
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let queryStart = trimmed.firstIndex(of: "?")
        components.path = basePath + Self.apiPath + (queryStart.map { String(trimmed[..<$0]) } ?? trimmed)
        components.percentEncodedQuery = queryStart.map { String(trimmed[trimmed.index(after: $0)...]) }
        guard let url = components.url else { throw TestJuiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Sends a request and returns the raw response body for 2xx responses.
    public func send(method: String, path: String, body: Data? = nil) async throws -> Data {
        try await send(request: makeRequest(method: method, path: path, body: body))
    }

    func makeResultRequest(
        _ result: TestJuiceTestResult,
        telemetry: TestJuiceDeviceTelemetry? = nil
    ) throws -> URLRequest {
        try makeRequest(
            method: "POST",
            path: "/tests/results",
            body: JSONEncoder().encode(result.withTelemetry(telemetry)))
    }

    func send(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TestJuiceError.make(statusCode: http.statusCode, responseBody: data)
        }
        return data
    }

    public func get<Response: Decodable>(_ path: String, as type: Response.Type = Response.self) async throws -> Response {
        let data = try await send(method: "GET", path: path)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    public func post<Request: Encodable, Response: Decodable>(
        _ path: String, body: Request, as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await send(method: "POST", path: path, body: try JSONEncoder().encode(body))
        return try JSONDecoder().decode(Response.self, from: data)
    }

    struct TestDefinitionResponse: Decodable, Sendable {
        let showPassFailButtons: Bool
        let reward: SdkRewardInfo?
    }

    func makeDefinitionRequest(testType: TestJuiceTestType, codeword: String) throws -> URLRequest {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        let encoded = codeword.addingPercentEncoding(withAllowedCharacters: allowed) ?? codeword
        return try makeRequest(method: "GET", path: "/tests?testType=\(testType.rawValue)&codeword=\(encoded)")
    }

    /// Whether the backend allows Pass/Fail buttons for this test (`showPassFailButtons`).
    public func fetchShowPassFailButtons(testType: TestJuiceTestType, codeword: String) async throws -> Bool {
        try await fetchTestDefinition(testType: testType, codeword: codeword).showPassFailButtons
    }

    func fetchTestDefinition(testType: TestJuiceTestType, codeword: String) async throws -> TestDefinitionResponse {
        let data = try await send(request: makeDefinitionRequest(testType: testType, codeword: codeword))
        return try JSONDecoder().decode(TestDefinitionResponse.self, from: data)
    }

    struct TestResultResponse: Decodable, Sendable {
        let testRecordId: Int
        let status: String
    }

    func makeVideoRequestURL(testRecordId: Int) throws -> URL {
        guard let url = try makeRequest(method: "POST", path: "/tests/\(testRecordId)/video").url else {
            throw TestJuiceError.invalidURL
        }
        return url
    }

    /// Submits the result as JSON, then attaches the recording to the created test record.
    public func submitTestResult(
        _ result: TestJuiceTestResult,
        telemetry: TestJuiceDeviceTelemetry? = nil,
        videoURL: URL? = nil,
        crashLogURL: URL? = nil
    ) async throws {
        let data = try await send(request: makeResultRequest(result, telemetry: telemetry))
        guard videoURL != nil || crashLogURL != nil else { return }

        let response = try JSONDecoder().decode(TestResultResponse.self, from: data)
        if let videoURL {
            let endpoint = try makeVideoRequestURL(testRecordId: response.testRecordId)
            try await SessionUploader(apiKey: configuration.apiKey, endpoint: endpoint, session: session)
                .upload(videoURL: videoURL)
        }
        if let crashLogURL {
            // Best effort: the result itself has already been recorded.
            if let endpoint = try? makeRequest(
                method: "POST", path: "/tests/\(response.testRecordId)/crash-log").url {
                try? await SessionUploader(apiKey: configuration.apiKey, endpoint: endpoint, session: session)
                    .upload(fileURL: crashLogURL, field: "crashLog", mimeType: "text/plain")
            }
        }
    }
}

private extension TestJuiceTestResult {
    func withTelemetry(_ telemetry: TestJuiceDeviceTelemetry?) -> Self {
        var result = self
        result.telemetry = telemetry
        return result
    }
}
