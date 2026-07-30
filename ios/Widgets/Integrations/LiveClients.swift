import Foundation
import AuthenticationServices
import WidgetsShared

/// Thin façades that conform the concrete `enum` integration clients to
/// the `StravaAPI` / `HealthDataReading` / `TogglAPI` protocols. The production
/// `IntegrationContainer` is composed of these. They forward every call
/// directly to the static methods on the underlying enum so production
/// behaviour is byte-identical to pre-protocol code.

struct LiveStravaClient: StravaAPI {
    @MainActor
    func authenticate(
        presentationAnchor: ASPresentationAnchor,
        workerBaseURL: URL
    ) async throws -> StravaTokens {
        try await StravaClient.authenticate(
            presentationAnchor: presentationAnchor,
            workerBaseURL: workerBaseURL
        )
    }

    func refresh(
        workerBaseURL: URL,
        refreshToken: String
    ) async throws -> StravaTokens {
        try await StravaClient.refresh(
            workerBaseURL: workerBaseURL,
            refreshToken: refreshToken
        )
    }

    func dailyActivityMinutes(
        accessToken: String,
        since: Date,
        until: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        try await StravaClient.dailyActivityMinutes(
            accessToken: accessToken,
            since: since,
            until: until,
            timeZone: timeZone
        )
    }

    func dailyActivityMinutes(
        accessToken: String,
        since: Date,
        until: Date,
        timeZone: TimeZone,
        refreshAccessToken: (@Sendable () async throws -> String)?
    ) async throws -> [String: Double] {
        try await StravaClient.dailyActivityMinutes(
            accessToken: accessToken,
            since: since,
            until: until,
            timeZone: timeZone,
            refreshAccessToken: refreshAccessToken
        )
    }
}

/// Production `TogglAPI` implementation. Reads the stored token from
/// `IntegrationCredentials.Toggl` and delegates to `TogglClient`.
struct LiveTogglClient: TogglAPI {
    func validateToken() async throws -> Bool {
        guard let storedToken = IntegrationCredentials.Toggl.token() else {
            return false
        }
        let client = TogglClient(token: storedToken)
        return try await client.validateToken()
    }

    func dailyTrackedHours(
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        guard let storedToken = IntegrationCredentials.Toggl.token() else {
            return [:]
        }
        let client = TogglClient(token: storedToken)
        return try await client.dailyTrackedHours(start: start, end: end, timeZone: timeZone)
    }
}

struct LiveHealthClient: HealthDataReading {
    func requestAuthorization() async throws -> Bool {
        try await HealthKitReader.requestAuthorization()
    }

    func dailySteps(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        try await HealthKitReader.dailySteps(
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    func dailyWorkoutMinutes(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        try await HealthKitReader.dailyWorkoutMinutes(
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    func dailySleep(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        try await HealthKitReader.dailySleep(
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    func dailyActiveEnergy(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        try await HealthKitReader.dailyActiveEnergy(
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    func dailyMindfulMinutes(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        try await HealthKitReader.dailyMindfulMinutes(
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    func dailyHRV(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        try await HealthKitReader.dailyHRV(
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    func dailyRestingHR(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        try await HealthKitReader.dailyRestingHR(
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    func dailyBodyMass(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        try await HealthKitReader.dailyBodyMass(
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }
}
