import Foundation

enum AppleSignInEmail {
    static func resolve(credentialEmail: String?, identityToken: Data?) -> String? {
        if let credentialEmail, !credentialEmail.isEmpty {
            return credentialEmail
        }

        guard let identityToken,
              let jwt = String(data: identityToken, encoding: .utf8)
        else { return nil }

        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = claims["email"] as? String, !email.isEmpty
        else { return nil }
        return email
    }
}
