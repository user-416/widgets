import XCTest
@testable import Widgets

final class StravaClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.reset()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testRefreshHitsWorkerWithRefreshToken() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertTrue(request.url?.absoluteString.hasSuffix("/strava/refresh") ?? false)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = """
            {"access_token":"new_at","refresh_token":"new_rt","expires_at":1745725600,"athlete":{"id":42}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let workerURL = URL(string: "https://example.workers.dev")!
        let tokens = try await StravaClient.refresh(workerBaseURL: workerURL, refreshToken: "old_rt")
        XCTAssertEqual(tokens.accessToken, "new_at")
        XCTAssertEqual(tokens.refreshToken, "new_rt")
        XCTAssertEqual(tokens.athleteId, 42)
    }

    func testDailyActivityMinutesAggregatesPerLocalDay() async throws {
        // Three activities, two on the same UTC day, one the next day.
        let body = """
        [
          {"id":1,"elapsed_time":1800,"start_date":"2026-04-26T08:00:00Z","type":"Run"},
          {"id":2,"elapsed_time":900,"start_date":"2026-04-26T18:00:00Z","type":"Run"},
          {"id":3,"elapsed_time":3600,"start_date":"2026-04-27T07:30:00Z","type":"Ride"}
        ]
        """.data(using: .utf8)!
        let emptyBody = "[]".data(using: .utf8)!

        var page = 0
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let returned: Data = page == 0 ? body : emptyBody
            page += 1
            return (response, returned)
        }

        let buckets = try await StravaClient.dailyActivityMinutes(
            accessToken: "tok",
            since: Date(timeIntervalSince1970: 1_745_625_600),
            until: Date(timeIntervalSince1970: 1_745_798_400),
            timeZone: TimeZone(identifier: "UTC") ?? .current
        )

        XCTAssertEqual(buckets["2026-04-26"], 45, "30min + 15min should sum to 45")
        XCTAssertEqual(buckets["2026-04-27"], 60, "60min")
        XCTAssertGreaterThanOrEqual(MockURLProtocol.requests.count, 2)
    }

    func testRateLimitErrorParsesRetryAfter() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "120"]
            )!
            return (response, Data())
        }
        do {
            _ = try await StravaClient.dailyActivityMinutes(
                accessToken: "tok",
                since: Date(timeIntervalSinceNow: -86400)
            )
            XCTFail("Expected throw")
        } catch StravaClient.StravaError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 120)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - OAuth callback CSRF state

    func testParseCallbackExtractsCodeWhenStateMatches() throws {
        let state = "state_xyz"
        let url = URL(string: "widgets://localhost/strava-callback?code=ac_abc&state=\(state)&scope=read")!
        let result = try StravaClient.parseCallback(url, expectedState: state)
        XCTAssertEqual(result.code, "ac_abc")
        XCTAssertEqual(result.state, state)
    }

    func testParseCallbackThrowsOnStateMismatch() {
        // Attacker delivered a callback with a code they minted + their own state.
        let url = URL(string: "widgets://localhost/strava-callback?code=injected&state=evil")!
        do {
            _ = try StravaClient.parseCallback(url, expectedState: "we_expected_this")
            XCTFail("Expected stateMismatch")
        } catch StravaClient.StravaError.stateMismatch {
            // ok
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testParseCallbackSurfacesUserDenialBeforeStateCheck() {
        // User tapped "Cancel" on Strava's consent screen — Strava sends `error=access_denied`
        // and may omit `state`. We surface the error rather than the state mismatch so the
        // UI shows "you denied access" and not "we suspect a CSRF attack".
        let url = URL(string: "widgets://localhost/strava-callback?error=access_denied")!
        do {
            _ = try StravaClient.parseCallback(url, expectedState: "anything")
            XCTFail("Expected oauthError")
        } catch StravaClient.StravaError.oauthError(let msg) {
            XCTAssertEqual(msg, "access_denied")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testParseCallbackThrowsMissingCodeWhenStateValidButNoCode() {
        let state = "ok"
        let url = URL(string: "widgets://localhost/strava-callback?state=\(state)")!
        do {
            _ = try StravaClient.parseCallback(url, expectedState: state)
            XCTFail("Expected oauthError(missing_code)")
        } catch StravaClient.StravaError.oauthError(let msg) {
            XCTAssertEqual(msg, "missing_code")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - Refresh worker error envelope

    func testRefreshSurfacesWorkerErrorEnvelope() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            let body = "{\"error\":\"strava_error\"}".data(using: .utf8)!
            return (response, body)
        }
        do {
            _ = try await StravaClient.refresh(
                workerBaseURL: URL(string: "https://example.workers.dev")!,
                refreshToken: "stale"
            )
            XCTFail("Expected throw")
        } catch StravaClient.StravaError.oauthError(let msg) {
            XCTAssertEqual(msg, "strava_error")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - 401 mid-pagination (latent bug A3-4)

    func testDailyActivityMinutes401MidPaginationRetriesWithRefreshedToken() async throws {
        // Sequence:
        //   page=1 + Bearer stale → 200 + activities
        //   page=2 + Bearer stale → 401 (token expired between pages)
        //   refresh closure called → returns "fresh_at"
        //   page=2 + Bearer fresh_at → 200 + more activities
        //   page=3 + Bearer fresh_at → 200 + [] → loop ends
        let dayA: TimeInterval = 1_745_625_600 // 2025-04-26 UTC
        let dayB: TimeInterval = 1_745_712_000 // 2025-04-27 UTC

        let body1 = """
        [{"id":1,"elapsed_time":1800,"start_date":"2025-04-26T08:00:00Z","type":"Run"}]
        """.data(using: .utf8)!
        let body2Retry = """
        [{"id":2,"elapsed_time":3600,"start_date":"2025-04-27T08:00:00Z","type":"Ride"}]
        """.data(using: .utf8)!
        let bodyEmpty = "[]".data(using: .utf8)!

        var hits = 0
        MockURLProtocol.handler = { request in
            let bearer = request.value(forHTTPHeaderField: "Authorization") ?? ""
            let pageStr = (request.url?.query ?? "")
                .split(separator: "&")
                .first(where: { $0.hasPrefix("page=") })
                .map { String($0.dropFirst("page=".count)) } ?? "?"

            hits += 1
            switch (pageStr, bearer) {
            case ("1", "Bearer stale_at"):
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, body1)
            case ("2", "Bearer stale_at"):
                let r = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (r, Data())
            case ("2", "Bearer fresh_at"):
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, body2Retry)
            case ("3", "Bearer fresh_at"):
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, bodyEmpty)
            default:
                XCTFail("Unexpected request page=\(pageStr) bearer=\(bearer)")
                let r = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (r, Data())
            }
        }

        let refreshCalls = AtomicCounter()
        let buckets = try await StravaClient.dailyActivityMinutes(
            accessToken: "stale_at",
            since: Date(timeIntervalSince1970: dayA - 1),
            until: Date(timeIntervalSince1970: dayB + 86_400),
            timeZone: TimeZone(identifier: "UTC") ?? .current,
            refreshAccessToken: {
                refreshCalls.increment()
                return "fresh_at"
            }
        )

        XCTAssertEqual(refreshCalls.value, 1, "Refresh closure should fire exactly once on 401 mid-pagination")
        XCTAssertEqual(buckets["2025-04-26"], 30, "Page 1 activity (30min) preserved across refresh")
        XCTAssertEqual(buckets["2025-04-27"], 60, "Page 2 activity (60min) recovered after refresh")
        XCTAssertEqual(hits, 4, "Exactly 4 HTTP attempts: page1 OK, page2 401, page2 retry OK, page3 empty")
    }

    func testDailyActivityMinutes401WithoutRefreshClosureStillThrows() async {
        // Belt-and-suspenders: when no refresh closure is provided, behavior
        // matches the pre-fix code path — surfaces invalidResponse.
        MockURLProtocol.handler = { request in
            let r = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (r, Data())
        }
        do {
            _ = try await StravaClient.dailyActivityMinutes(
                accessToken: "stale",
                since: Date(timeIntervalSinceNow: -86_400)
            )
            XCTFail("Expected throw")
        } catch StravaClient.StravaError.invalidResponse {
            // Pass.
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testDailyActivityMinutes401TwiceFailsAfterSingleRetry() async {
        // Refresh closure runs once; if the fresh token also 401s, we don't
        // loop forever — surface invalidResponse.
        MockURLProtocol.handler = { request in
            let r = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (r, Data())
        }
        let refreshCalls = AtomicCounter()
        do {
            _ = try await StravaClient.dailyActivityMinutes(
                accessToken: "a",
                since: Date(timeIntervalSinceNow: -86_400),
                refreshAccessToken: {
                    refreshCalls.increment()
                    return "b"
                }
            )
            XCTFail("Expected throw")
        } catch StravaClient.StravaError.invalidResponse {
            XCTAssertEqual(refreshCalls.value, 1, "Refresh must only fire once even on persistent 401")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - Rate-limit header surfacing (latent bug A3-5)

    func testRateLimitHeadersAreParsedAndExposedAfterSuccessfulRequest() async throws {
        await StravaRateLimitTracker.shared.reset()

        MockURLProtocol.handler = { request in
            let r = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "X-RateLimit-Limit": "100,1000",
                    "X-RateLimit-Usage": "85,50"
                ]
            )!
            return (r, "[]".data(using: .utf8)!)
        }

        _ = try await StravaClient.dailyActivityMinutes(
            accessToken: "tok",
            since: Date(timeIntervalSinceNow: -86_400)
        )

        let latest = await StravaRateLimitTracker.shared.latest
        XCTAssertNotNil(latest, "Tracker should have absorbed the headers from the response")
        XCTAssertEqual(latest?.shortLimit, 100)
        XCTAssertEqual(latest?.shortUsage, 85)
        XCTAssertEqual(latest?.longLimit, 1000)
        XCTAssertEqual(latest?.longUsage, 50)
        XCTAssertEqual(latest?.shortRemaining, 15)
        XCTAssertEqual(latest?.longRemaining, 950)
        XCTAssertTrue(latest?.nearLimit ?? false, "85/100 short window crosses 80% near-limit threshold")
    }

    func testRateLimitParserRejectsMalformedHeaders() {
        let okResponse = HTTPURLResponse(
            url: URL(string: "https://x")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["X-RateLimit-Limit": "100", "X-RateLimit-Usage": "5"] // missing long value
        )!
        XCTAssertNil(StravaRateLimit.parse(from: okResponse))

        let missing = HTTPURLResponse(
            url: URL(string: "https://x")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        XCTAssertNil(StravaRateLimit.parse(from: missing))

        let normal = HTTPURLResponse(
            url: URL(string: "https://x")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["X-RateLimit-Limit": "100,1000", "X-RateLimit-Usage": "10,20"]
        )!
        let info = StravaRateLimit.parse(from: normal)
        XCTAssertEqual(info?.shortLimit, 100)
        XCTAssertFalse(info?.nearLimit ?? true, "10/100 short and 20/1000 long are well under 80%")
    }
}
