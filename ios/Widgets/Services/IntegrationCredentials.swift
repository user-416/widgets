import Foundation

enum IntegrationCredentials {

    /// Toggl Track API token (no refresh, no expiry — token is long-lived).
    /// Token is a 32-hex-char string obtained from track.toggl.com → Profile → API Token.
    enum Toggl {
        private static let keychainKey = "integration.toggl.token"

        /// Stores the plaintext API token in the Keychain.
        static func store(_ token: String) throws {
            try Keychain.store(token, forKey: keychainKey)
        }

        /// Retrieves the API token from the Keychain, or `nil` if not set.
        static func token() -> String? {
            Keychain.retrieve(forKey: keychainKey)
        }

        /// Removes the token from the Keychain (disconnect flow).
        static func disconnect() throws {
            try Keychain.delete(forKey: keychainKey)
        }
    }

    enum Strava {
        private static let bundleKey = "integration.strava.tokens"

        static func store(_ tokens: StravaTokens) throws {
            let data = try JSONEncoder().encode(tokens)
            guard let json = String(data: data, encoding: .utf8) else {
                throw Keychain.KeychainError.unexpectedStatus(errSecParam)
            }
            try Keychain.store(json, forKey: bundleKey)
        }

        static func tokens() -> StravaTokens? {
            guard let json = Keychain.retrieve(forKey: bundleKey),
                  let data = json.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(StravaTokens.self, from: data)
        }

        static func disconnect() throws {
            try Keychain.delete(forKey: bundleKey)
        }
    }
}
