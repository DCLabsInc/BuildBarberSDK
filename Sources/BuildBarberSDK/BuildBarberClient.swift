import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Configuration for talking to the BuildBarber REST API.
public struct BuildBarberConfiguration: Sendable {
    /// Use the portal host: buildbarber.com redirects to it, which breaks POST requests.
    public static let defaultBaseURL = URL(string: "https://portal.buildbarber.com")!

    /// "iOS SDK API key" generated in BuildBarber Settings.
    public var apiKey: String
    public var baseURL: URL

    public init(apiKey: String, baseURL: URL = BuildBarberConfiguration.defaultBaseURL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }
}

public enum BuildBarberTestType: String, Codable, Sendable {
    case feature = "Feature"
    case release = "Release"
}

public struct BuildBarberTest: Decodable, Sendable {
    public struct ChecklistItem: Decodable, Sendable {
        public let key: String
        public let label: String
        public let kind: String
    }

    public let title: String
    public let instructions: String
    public let checklist: [ChecklistItem]
    public let showPassFailButtons: Bool
}

public struct BuildBarberTestResult: Encodable, Sendable {
    public let testType: BuildBarberTestType
    public let codeword: String
    public let testerEmail: String
    public let outcome: String?
    public let feedback: String
    public let checkedItems: [String]

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(testType, forKey: .testType)
        try container.encode(codeword, forKey: .codeword)
        try container.encode(testerEmail, forKey: .testerEmail)
        try container.encodeIfPresent(outcome, forKey: .outcome)
        try container.encode(feedback, forKey: .feedback)
        try container.encode(checkedItems, forKey: .checkedItems)
    }

    private enum CodingKeys: String, CodingKey {
        case testType
        case codeword
        case testerEmail
        case outcome
        case feedback
        case checkedItems
    }
}

/// Error body returned by the API: `{ "error": "<code>", "message": "<text>" }`.
public struct APIErrorBody: Codable, Sendable, Equatable {
    public let error: String
    public let message: String?
}

public enum BuildBarberError: Error, LocalizedError, Sendable, Equatable {
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

extension BuildBarberError {
    static func make(statusCode: Int, responseBody: Data) -> BuildBarberError {
        if let apiError = try? JSONDecoder().decode(APIErrorBody.self, from: responseBody) {
            return .api(status: statusCode, body: apiError)
        }
        let text = String(decoding: responseBody.prefix(4096), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .badStatus(statusCode) : .http(status: statusCode, text: text)
    }
}

/// Minimal client for `/api/sdk/v1`. JSON is camelCase in both directions.
public struct BuildBarberClient: Sendable {
    public static let apiPath = "/api/sdk/v1"

    public let configuration: BuildBarberConfiguration
    private let session: URLSession

    public init(configuration: BuildBarberConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func makeRequest(method: String, path: String, body: Data? = nil) throws -> URLRequest {
        let trimmed = path.hasPrefix("/") ? path : "/" + path
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw BuildBarberError.invalidURL
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let queryStart = trimmed.firstIndex(of: "?")
        components.path = basePath + Self.apiPath + (queryStart.map { String(trimmed[..<$0]) } ?? trimmed)
        components.percentEncodedQuery = queryStart.map { String(trimmed[trimmed.index(after: $0)...]) }
        guard let url = components.url else { throw BuildBarberError.invalidURL }

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

    func makeResultRequest(_ result: BuildBarberTestResult) throws -> URLRequest {
        try makeRequest(
            method: "POST",
            path: "/tests/results",
            body: JSONEncoder().encode(result))
    }

    func send(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BuildBarberError.make(statusCode: http.statusCode, responseBody: data)
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
    }

    func makeDefinitionRequest(testType: BuildBarberTestType, codeword: String) throws -> URLRequest {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        let encoded = codeword.addingPercentEncoding(withAllowedCharacters: allowed) ?? codeword
        return try makeRequest(method: "GET", path: "/tests?testType=\(testType.rawValue)&codeword=\(encoded)")
    }

    /// Whether the backend allows Pass/Fail buttons for this test (`showPassFailButtons`).
    public func fetchShowPassFailButtons(testType: BuildBarberTestType, codeword: String) async throws -> Bool {
        let data = try await send(request: makeDefinitionRequest(testType: testType, codeword: codeword))
        return try JSONDecoder().decode(TestDefinitionResponse.self, from: data).showPassFailButtons
    }

    struct TestResultResponse: Decodable, Sendable {
        let testRecordId: Int
        let status: String
    }

    func makeVideoRequestURL(testRecordId: Int) throws -> URL {
        guard let url = try makeRequest(method: "POST", path: "/tests/\(testRecordId)/video").url else {
            throw BuildBarberError.invalidURL
        }
        return url
    }

    /// Submits the result as JSON, then attaches the recording to the created test record.
    public func submitTestResult(
        _ result: BuildBarberTestResult, videoURL: URL? = nil, crashLogURL: URL? = nil
    ) async throws {
        let data = try await send(request: makeResultRequest(result))
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
