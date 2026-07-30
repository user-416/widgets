import Foundation

/// Tokens issued by the Strava OAuth flow. Persisted in the Keychain via
/// `IntegrationCredentials.Strava` and refreshed before expiry by `SyncCoordinator`.
struct StravaTokens: Sendable, Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let athleteId: Int64?
}
