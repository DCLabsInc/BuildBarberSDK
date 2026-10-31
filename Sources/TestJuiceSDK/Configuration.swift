import Foundation

/// Reads the SDK API key from the host app's Info.plist, where it is injected
/// from a git-ignored `Config.xcconfig` via `SDKAPIKey = $(SDK_API_KEY)`.
public enum TestJuiceAppConfiguration {
    public static let apiKeyInfoPlistKey = "SDKAPIKey"

    /// Returns the API key, or `nil` if it is missing, empty, or an unresolved
    /// build-setting placeholder such as `$(SDK_API_KEY)`.
    public static func apiKey(from infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> String? {
        guard let value = infoDictionary?[apiKeyInfoPlistKey] as? String else { return nil }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }
}
