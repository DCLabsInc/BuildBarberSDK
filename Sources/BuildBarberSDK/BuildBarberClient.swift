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

/// Error body returned by the API: `{ "error": "<code>", "message": "<text>" }`.
public struct APIErrorBody: Codable, Sendable, Equatable {
    public let error: String
    public let message: String?
}

public enum BuildBarberError: Error, Sendable, Equatable {
    case invalidURL
    case api(status: Int, body: APIErrorBody)
    case badStatus(Int)
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
        let request = try makeRequest(method: method, path: path, body: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if let apiError = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                throw BuildBarberError.api(status: http.statusCode, body: apiError)
            }
            throw BuildBarberError.badStatus(http.statusCode)
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
}
