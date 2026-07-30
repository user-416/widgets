import Foundation
import OSLog
import WidgetsShared

/// Toggl Track API v9 client. Token-only (HTTP Basic auth) — no OAuth.
///
/// Auth scheme: `Authorization: Basic base64("<token>:api_token")` where
/// the literal string `api_token` is always the password field.
///
/// Usage:
/// ```swift
/// let client = TogglClient(token: storedToken, session: urlSession)
/// let valid  = try await client.validateToken()
/// let hours  = try await client.dailyTrackedHours(start: since, end: until, timeZone: .current)
/// ```
struct TogglClient {

    // MARK: - API surfaces

    private static let meURL = "https://api.track.toggl.com/api/v9/me"
    private static let timeEntriesURL = "https://api.track.toggl.com/api/v9/me/time_entries"
    private static let logger = Logger(subsystem: "io.github.user-416.widgets", category: "Toggl")

    enum TogglError: Error {
        case invalidToken
        case networkError(any Error)
        case rateLimited(retryAfter: TimeInterval?)
        case invalidResponse
    }

    let token: String
    let session: URLSession

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    // MARK: - Token validation

    /// Returns `true` on 200, `false` on 403. Throws on network error or unexpected status.
    func validateToken() async throws -> Bool {
        guard let url = URL(string: Self.meURL) else {
            throw TogglError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeader(for: token), forHTTPHeaderField: "Authorization")

        let (_, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw TogglError.invalidResponse
        }
        switch http.statusCode {
        case 200: return true
        case 403: return false
        default:
            Self.logger.error("validateToken HTTP \(http.statusCode)")
            throw TogglError.invalidResponse
        }
    }

    // MARK: - Time entries / day bucketing

    /// Fetches all time entries in [start, end) and sums duration per local calendar day.
    /// Value is **hours** (seconds / 3600) per `SnapshotMetric.dateKey`.
    ///
    /// Pagination: Toggl returns up to 1000 entries per request. We page in 30-day
    /// windows to stay well under that limit for any realistic account.
    func dailyTrackedHours(
        start: Date,
        end: Date,
        timeZone: TimeZone = .current
    ) async throws -> [String: Double] {
        var buckets: [String: Double] = [:]
        let isoDay = Self.isoDateFormatter()
        let isoDateTime = ISO8601DateFormatter()
        isoDateTime.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoDateTimeNoFrac = ISO8601DateFormatter()
        isoDateTimeNoFrac.formatOptions = [.withInternetDateTime]

        // Page in 30-day windows.
        let windowDays: TimeInterval = 30 * 86_400
        var windowStart = start
        while windowStart < end {
            let windowEnd = min(windowStart.addingTimeInterval(windowDays), end)

            guard var components = URLComponents(string: Self.timeEntriesURL) else {
                throw TogglError.invalidResponse
            }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            components.queryItems = [
                URLQueryItem(name: "start_date", value: isoDay.string(from: windowStart)),
                URLQueryItem(name: "end_date", value: isoDay.string(from: windowEnd)),
            ]
            guard let url = components.url else {
                throw TogglError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(authHeader(for: token), forHTTPHeaderField: "Authorization")

            let (data, response) = try await performRequest(request)
            guard let http = response as? HTTPURLResponse else {
                throw TogglError.invalidResponse
            }
            switch http.statusCode {
            case 200: break
            case 403: throw TogglError.invalidToken
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                throw TogglError.rateLimited(retryAfter: retryAfter)
            default:
                Self.logger.error("time_entries HTTP \(http.statusCode)")
                throw TogglError.invalidResponse
            }

            let entries: [TogglTimeEntry]
            do {
                entries = try JSONDecoder().decode([TogglTimeEntry].self, from: data)
            } catch {
                Self.logger.error("decode time_entries: \(error.localizedDescription)")
                throw TogglError.invalidResponse
            }

            for entry in entries {
                // Skip running entries: duration is negative when the timer is still running.
                // Also skip if stop is nil (belt-and-suspenders).
                guard entry.duration >= 0, entry.stop != nil else { continue }

                // Parse start timestamp.
                let startDate = isoDateTime.date(from: entry.start)
                    ?? isoDateTimeNoFrac.date(from: entry.start)
                guard let startDate else {
                    Self.logger.notice("Unparseable start date: \(entry.start)")
                    continue
                }

                // Attribute full duration to the start day (Toggl dashboard convention).
                let key = SnapshotMetric.dateKey(for: startDate, timeZone: timeZone)
                let hours = Double(entry.duration) / 3600.0
                buckets[key, default: 0] += hours
            }

            windowStart = windowEnd
        }

        return buckets
    }

    // MARK: - Helpers

    /// Builds the HTTP Basic auth header value for Toggl's fixed scheme.
    /// The "password" field is always the literal string `api_token`.
    func authHeader(for token: String) -> String {
        let raw = "\(token):api_token"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    /// Wraps `session.data(for:)` and maps network errors to `TogglError.networkError`.
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw TogglError.networkError(error)
        }
    }

    /// ISO 8601 date-only formatter (`YYYY-MM-DD`) in UTC, suitable for Toggl's
    /// `start_date` / `end_date` query params.
    static func isoDateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }
}

// MARK: - Decodable models

private struct TogglTimeEntry: Decodable {
    let id: Int64
    let start: String
    let stop: String?
    let duration: Int  // seconds; negative == currently running
}
