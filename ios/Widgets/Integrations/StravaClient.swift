import Foundation
import AuthenticationServices
import CryptoKit
import OSLog
import WidgetsShared

enum StravaClient {

    /// Strava app client ID. Read from `STRAVA_CLIENT_ID` in `Info.plist`. In DEBUG
    /// builds, falls back to a documented placeholder so the build still compiles
    /// while the real value is being wired up — production reads return `nil`,
    /// which the AddStrava flow surfaces as a configuration error.
    static var clientID: String? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "STRAVA_CLIENT_ID") as? String,
           !raw.isEmpty {
            return raw
        }
        #if DEBUG
        Self.debugClientIDWarning.flag()
        return "123456"
        #else
        return nil
        #endif
    }

    /// Strava validates the redirect URI by parsing the host and comparing
    /// it to the "Authorization Callback Domain" registered for the app.
    /// We register `localhost` (Strava's docs recommend it for development),
    /// so the host portion of this URI must be `localhost`. The path segment
    /// (`/strava-callback`) is just for our own routing; iOS dispatches the
    /// callback to our app via `CFBundleURLSchemes: [widgets]` and we match
    /// the path in the OAuth handler.
    static let redirectURI = "widgets://localhost/strava-callback"
    static let scope = "activity:read"

    private static let logger = Logger(subsystem: "io.github.user-416.widgets", category: "Strava")
    #if DEBUG
    private actor DebugWarningOnce {
        var fired = false
        func flag() {
            guard !fired else { return }
            fired = true
            Logger(subsystem: "io.github.user-416.widgets", category: "Strava")
                .warning("STRAVA_CLIENT_ID not set in Info.plist; using DEBUG placeholder '123456'")
        }
    }
    private static let debugClientIDWarningActor = DebugWarningOnce()
    private struct DebugWarningOncePoint {
        func flag() { Task { await debugClientIDWarningActor.flag() } }
    }
    private static let debugClientIDWarning = DebugWarningOncePoint()
    #endif
    private static let authorizeURL = "https://www.strava.com/oauth/authorize"
    private static let activitiesURL = "https://www.strava.com/api/v3/athlete/activities"
    private static let callbackScheme = "widgets"
    private static let activityPageSize = 100

    enum StravaError: Error {
        case userCancelled
        case oauthError(String)
        case networkError(any Error)
        case rateLimited(retryAfter: TimeInterval?)
        case invalidResponse
        /// CSRF guard tripped: the `state` echoed in the callback URL didn't
        /// match the one we generated when starting the flow. Implies an
        /// authorization-code injection attempt or a stale callback.
        case stateMismatch
    }

    @MainActor
    static func authenticate(
        presentationAnchor: ASPresentationAnchor,
        workerBaseURL: URL
    ) async throws -> StravaTokens {
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = codeChallenge(for: codeVerifier)
        // CSRF guard: PKCE protects token exchange against a malicious app
        // intercepting the auth code, but doesn't protect the redirect itself
        // against an attacker getting Widgets to consume an auth code they
        // already minted. The `state` parameter closes that gap — Strava
        // echoes whatever we sent, and we verify it matches before exchange.
        let state = generateStateToken()

        guard let resolvedClientID = clientID else {
            throw StravaError.oauthError("STRAVA_CLIENT_ID not configured in Info.plist")
        }
        guard var components = URLComponents(string: authorizeURL) else {
            throw StravaError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: resolvedClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "approval_prompt", value: "force"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let authURL = components.url else {
            throw StravaError.invalidResponse
        }

        let callbackURL = try await presentSession(
            url: authURL,
            anchor: presentationAnchor
        )

        let (code, _) = try parseCallback(callbackURL, expectedState: state)
        return try await exchange(
            workerBaseURL: workerBaseURL,
            code: code,
            codeVerifier: codeVerifier
        )
    }

    /// Parses Strava's redirect URL, validates the `state` parameter against
    /// the one we sent, and returns the auth code. Public for tests so we can
    /// verify CSRF logic without spinning up `ASWebAuthenticationSession`.
    /// Returns `(code, state)` on success.
    static func parseCallback(_ url: URL, expectedState: String) throws -> (code: String, state: String) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw StravaError.invalidResponse
        }
        let items = components.queryItems ?? []

        // Strava puts the user's "Cancel" / "Deny" outcome in the `error`
        // param (e.g. "access_denied"). Surface it before any state check —
        // there is no auth code in this case anyway, and the state token may
        // legitimately be missing on certain error paths.
        if let err = items.first(where: { $0.name == "error" })?.value, !err.isEmpty {
            throw StravaError.oauthError(err)
        }

        let stateValue = items.first(where: { $0.name == "state" })?.value ?? ""
        if stateValue != expectedState {
            throw StravaError.stateMismatch
        }

        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw StravaError.oauthError("missing_code")
        }
        return (code, stateValue)
    }

    /// 32 URL-safe random characters. Used as the OAuth `state` token (CSRF guard).
    private static func generateStateToken() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for i in 0..<bytes.count {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func refresh(workerBaseURL: URL, refreshToken: String) async throws -> StravaTokens {
        let url = workerBaseURL.appendingPathComponent("strava/refresh")
        let body: [String: String] = ["refresh_token": refreshToken]
        return try await postWorker(url: url, body: body)
    }

    static func dailyActivityMinutes(
        accessToken: String,
        since: Date,
        until: Date = .now,
        timeZone: TimeZone = .current,
        refreshAccessToken: (@Sendable () async throws -> String)? = nil
    ) async throws -> [String: Double] {
        let after = Int(since.timeIntervalSince1970)
        let before = Int(until.timeIntervalSince1970)
        let isoParser = ISO8601DateFormatter()
        isoParser.formatOptions = [.withInternetDateTime]

        var buckets: [String: Double] = [:]
        var page = 1
        var currentToken = accessToken
        var didRefresh = false

        pageLoop: while true {
            guard var components = URLComponents(string: activitiesURL) else {
                throw StravaError.invalidResponse
            }
            components.queryItems = [
                URLQueryItem(name: "after", value: String(after)),
                URLQueryItem(name: "before", value: String(before)),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(activityPageSize)),
            ]
            guard let url = components.url else {
                throw StravaError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw StravaError.networkError(error)
            }

            guard let http = response as? HTTPURLResponse else {
                throw StravaError.invalidResponse
            }

            // Surface rate-limit headers regardless of status (Strava sets them
            // on every response, including 401/429). Lets the UI render
            // proactive "near limit" hints before we hit a hard 429.
            if let info = StravaRateLimit.parse(from: http) {
                await StravaRateLimitTracker.shared.update(info)
            }

            switch http.statusCode {
            case 200:
                break
            case 401:
                // Mid-pagination token expiry. If we have a way to refresh and
                // we haven't already burnt our one retry, do so and retry the
                // same page. Otherwise surface as invalid response (the caller
                // can re-auth or fall back to cached data).
                guard let refreshAccessToken, !didRefresh else {
                    logger.error("activities 401 page=\(page) didRefresh=\(didRefresh)")
                    throw StravaError.invalidResponse
                }
                didRefresh = true
                do {
                    currentToken = try await refreshAccessToken()
                    logger.notice("Strava 401 on page \(page); refreshed and retrying")
                    continue pageLoop
                } catch {
                    logger.error("Strava refresh-on-401 failed: \(error.localizedDescription)")
                    throw StravaError.invalidResponse
                }
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                throw StravaError.rateLimited(retryAfter: retryAfter)
            default:
                logger.error("activities HTTP \(http.statusCode)")
                throw StravaError.invalidResponse
            }

            let activities: [StravaActivity]
            do {
                activities = try JSONDecoder().decode([StravaActivity].self, from: data)
            } catch {
                logger.error("decode activities: \(error.localizedDescription)")
                throw StravaError.invalidResponse
            }

            if activities.isEmpty {
                break
            }

            for activity in activities {
                guard let start = isoParser.date(from: activity.startDate) else { continue }
                let key = SnapshotMetric.dateKey(for: start, timeZone: timeZone)
                buckets[key, default: 0] += Double(activity.elapsedTime) / 60.0
            }

            page += 1
        }

        return buckets
    }

    private static func exchange(
        workerBaseURL: URL,
        code: String,
        codeVerifier: String
    ) async throws -> StravaTokens {
        let url = workerBaseURL.appendingPathComponent("strava/exchange")
        let body: [String: String] = ["code": code, "code_verifier": codeVerifier]
        return try await postWorker(url: url, body: body)
    }

    private static func postWorker(url: URL, body: [String: String]) async throws -> StravaTokens {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw StravaError.invalidResponse
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw StravaError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            break
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw StravaError.rateLimited(retryAfter: retryAfter)
        default:
            if let envelope = try? JSONDecoder().decode(WorkerErrorEnvelope.self, from: data) {
                logger.error("worker error status=\(http.statusCode) error=\(envelope.error)")
                throw StravaError.oauthError(envelope.error)
            }
            logger.error("worker non-2xx status=\(http.statusCode)")
            throw StravaError.invalidResponse
        }

        let raw: StravaTokenResponse
        do {
            raw = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        } catch {
            logger.error("decode token: \(error.localizedDescription)")
            throw StravaError.invalidResponse
        }

        return StravaTokens(
            accessToken: raw.access_token,
            refreshToken: raw.refresh_token,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(raw.expires_at)),
            athleteId: raw.athlete?.id
        )
    }

    @MainActor
    private static func presentSession(
        url: URL,
        anchor: ASPresentationAnchor
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let provider = AnchorProvider(anchor: anchor)
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callback, error in
                if let error {
                    if let auth = error as? ASWebAuthenticationSessionError, auth.code == .canceledLogin {
                        continuation.resume(throwing: StravaError.userCancelled)
                    } else {
                        continuation.resume(throwing: StravaError.networkError(error))
                    }
                    return
                }
                guard let callback else {
                    continuation.resume(throwing: StravaError.invalidResponse)
                    return
                }
                continuation.resume(returning: callback)
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            withExtendedLifetime(provider) {
                _ = session.start()
            }
        }
    }

    private static func generateCodeVerifier() -> String {
        // Strava PKCE: 64 URL-safe chars from [A-Za-z0-9_-].
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var bytes = [UInt8](repeating: 0, count: 64)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for i in 0..<bytes.count {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }
        let chars = bytes.map { alphabet[Int($0) % alphabet.count] }
        return String(chars)
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        // base64url: '+' -> '-', '/' -> '_', strip '=' padding (RFC 7636).
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Snapshot of Strava's `X-RateLimit-Limit` / `X-RateLimit-Usage` pair.
/// Each value is "short,long" where short = 15-minute window and long = daily.
/// See https://developers.strava.com/docs/rate-limits/
struct StravaRateLimit: Sendable, Equatable {
    let shortLimit: Int
    let shortUsage: Int
    let longLimit: Int
    let longUsage: Int

    var shortRemaining: Int { max(0, shortLimit - shortUsage) }
    var longRemaining: Int { max(0, longLimit - longUsage) }

    /// True once either window crosses 80% — surfaces "near limit" UI hint.
    var nearLimit: Bool {
        let shortRatio = shortLimit > 0 ? Double(shortUsage) / Double(shortLimit) : 0
        let longRatio = longLimit > 0 ? Double(longUsage) / Double(longLimit) : 0
        return max(shortRatio, longRatio) >= 0.8
    }

    static func parse(from response: HTTPURLResponse) -> StravaRateLimit? {
        guard
            let limit = response.value(forHTTPHeaderField: "X-RateLimit-Limit"),
            let usage = response.value(forHTTPHeaderField: "X-RateLimit-Usage")
        else { return nil }
        let limitParts = limit
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let usageParts = usage
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard limitParts.count >= 2, usageParts.count >= 2 else { return nil }
        return StravaRateLimit(
            shortLimit: limitParts[0],
            shortUsage: usageParts[0],
            longLimit: limitParts[1],
            longUsage: usageParts[1]
        )
    }
}

/// Single source of truth for the most recently observed rate-limit window.
/// Updated after every Strava API response that carries the headers; read by
/// Settings/MetricDetail to render quota state without making an extra request.
actor StravaRateLimitTracker {
    static let shared = StravaRateLimitTracker()
    private(set) var latest: StravaRateLimit?

    func update(_ info: StravaRateLimit) {
        latest = info
    }

    func reset() {
        latest = nil
    }
}

private struct StravaTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_at: Int64
    let athlete: Athlete?

    struct Athlete: Decodable {
        let id: Int64?
    }
}

private struct WorkerErrorEnvelope: Decodable {
    let error: String
}

private struct StravaActivity: Decodable {
    let id: Int64
    let elapsedTime: Int
    let startDate: String
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id
        case elapsedTime = "elapsed_time"
        case startDate = "start_date"
        case type
    }
}

@MainActor
private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
