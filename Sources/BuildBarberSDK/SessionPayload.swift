import Foundation

/// A single checklist entry and its current state.
public struct ChecklistEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var title: String
    public var isTicked: Bool
}

/// JSON payload sent alongside the recording.
public struct SessionPayload: Codable, Sendable, Equatable {
    public struct Metadata: Codable, Sendable, Equatable {
        public var sessionID: String
        public var startedAt: Date
        public var endedAt: Date
        public var wasInterruptedByBackground: Bool
        public var appBundleID: String
        public var appVersion: String
        public var osVersion: String
        public var deviceModel: String
    }

    public var checklist: [ChecklistEntry]
    public var feedback: String
    public var metadata: Metadata
}

/// Builds multipart/form-data bodies.
public struct MultipartFormData: Sendable {
    public let boundary: String
    private var body = Data()

    public init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(name: String, value: Data, filename: String? = nil, mimeType: String? = nil) {
        var disposition = "Content-Disposition: form-data; name=\"\(name)\""
        if let filename { disposition += "; filename=\"\(filename)\"" }
        append("--\(boundary)\r\n\(disposition)\r\n")
        if let mimeType { append("Content-Type: \(mimeType)\r\n") }
        append("\r\n")
        body.append(value)
        append("\r\n")
    }

    public func finalized() -> Data {
        var data = body
        data.append(Data("--\(boundary)--\r\n".utf8))
        return data
    }

    private mutating func append(_ string: String) {
        body.append(Data(string.utf8))
    }
}
