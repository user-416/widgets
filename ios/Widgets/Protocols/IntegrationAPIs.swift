import Foundation
import AuthenticationServices

/// Abstract integration surfaces. Concrete production implementations live in
/// `Integrations/LiveClients.swift` and forward to the `enum` clients
/// (`StravaClient`, `HealthKitReader`). Fake (debug-only) implementations
/// live in `Fakes/`.

protocol StravaAPI: Sendable {
    @MainActor
    func authenticate(
        presentationAnchor: ASPresentationAnchor,
        workerBaseURL: URL
    ) async throws -> StravaTokens

    func refresh(
        workerBaseURL: URL,
        refreshToken: String
    ) async throws -> StravaTokens

    func dailyActivityMinutes(
        accessToken: String,
        since: Date,
        until: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double]

    /// Variant that lets the caller hand in a refresh closure used to recover
    /// from a 401 mid-pagination. Callers that don't care can use the 4-arg
    /// version; the default extension below drops the closure so existing
    /// conformers (fakes) don't need to change.
    func dailyActivityMinutes(
        accessToken: String,
        since: Date,
        until: Date,
        timeZone: TimeZone,
        refreshAccessToken: (@Sendable () async throws -> String)?
    ) async throws -> [String: Double]
}

extension StravaAPI {
    func dailyActivityMinutes(
        accessToken: String,
        since: Date,
        until: Date,
        timeZone: TimeZone,
        refreshAccessToken: (@Sendable () async throws -> String)?
    ) async throws -> [String: Double] {
        try await dailyActivityMinutes(
            accessToken: accessToken,
            since: since,
            until: until,
            timeZone: timeZone
        )
    }
}

protocol TogglAPI: Sendable {
    /// Validates the stored API token by hitting `GET /me`.
    /// Returns `true` on 200, `false` on 403 (bad token).
    func validateToken() async throws -> Bool

    /// Fetches tracked time entries and buckets them by local calendar day.
    /// Returns `[dateKey: hours]` where dateKey uses `SnapshotMetric.dateKey(...)` format.
    /// `start` is inclusive, `end` is exclusive (same convention as Toggl's API).
    func dailyTrackedHours(
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double]
}

protocol HealthDataReading: Sendable {
    func requestAuthorization() async throws -> Bool
    func dailySteps(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double]
    func dailyWorkoutMinutes(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double]
    func dailySleep(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double]
    func dailyActiveEnergy(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double]
    func dailyMindfulMinutes(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double]
    func dailyHRV(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double]
    func dailyRestingHR(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double]
    func dailyBodyMass(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double]
}
