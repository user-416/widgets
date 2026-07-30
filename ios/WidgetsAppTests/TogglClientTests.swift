import XCTest
@testable import Widgets

final class TogglClientTests: XCTestCase {

    // MARK: - URLSession configured to use MockURLProtocol

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    // MARK: - 1. Basic auth header

    func testAuthHeaderIsCorrectBase64() async throws {
        // Known token → expected header value.
        // "abcdef0123456789:api_token" in base64 is deterministic.
        let token = "abcdef0123456789"
        let expectedRaw = "\(token):api_token"
        let expectedEncoded = Data(expectedRaw.utf8).base64EncodedString()
        let expectedHeader = "Basic \(expectedEncoded)"

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), expectedHeader,
                           "Authorization header should be Basic base64(<token>:api_token)")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }

        let client = TogglClient(token: token, session: session)
        _ = try await client.validateToken()

        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    // MARK: - 2. Day bucketing across local days

    func testDayBucketingAcrossLocalDays() async throws {
        // 5 entries spanning 3 local days in UTC, including one "cross-midnight" entry.
        // All attributed to the start day (Toggl convention).
        // Day A: 2026-03-10  Day B: 2026-03-11  Day C: 2026-03-12
        let body = """
        [
          {"id":1,"start":"2026-03-10T09:00:00Z","stop":"2026-03-10T10:00:00Z","duration":3600},
          {"id":2,"start":"2026-03-10T14:30:00Z","stop":"2026-03-10T15:00:00Z","duration":1800},
          {"id":3,"start":"2026-03-10T23:30:00Z","stop":"2026-03-11T00:15:00Z","duration":2700},
          {"id":4,"start":"2026-03-11T08:00:00Z","stop":"2026-03-11T09:00:00Z","duration":3600},
          {"id":5,"start":"2026-03-12T10:00:00Z","stop":"2026-03-12T11:30:00Z","duration":5400}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let client = TogglClient(token: "testtoken", session: session)
        let tz = TimeZone(identifier: "UTC")!
        let start = makeDate("2026-03-10", tz: tz)
        let end   = makeDate("2026-03-13", tz: tz)
        let buckets = try await client.dailyTrackedHours(start: start, end: end, timeZone: tz)

        // Day A: 3600 + 1800 + 2700 = 8100s = 2.25h
        XCTAssertEqual(try XCTUnwrap(buckets["2026-03-10"]), 8100.0 / 3600.0, accuracy: 1e-9)
        // Day B: 3600s = 1.0h
        XCTAssertEqual(try XCTUnwrap(buckets["2026-03-11"]), 1.0, accuracy: 1e-9)
        // Day C: 5400s = 1.5h
        XCTAssertEqual(try XCTUnwrap(buckets["2026-03-12"]), 1.5, accuracy: 1e-9)
        XCTAssertEqual(buckets.count, 3)
    }

    // MARK: - 3. Running entry skipped (negative duration)

    func testRunningEntriesAreSkipped() async throws {
        let body = """
        [
          {"id":1,"start":"2026-03-10T09:00:00Z","stop":"2026-03-10T10:00:00Z","duration":3600},
          {"id":2,"start":"2026-03-10T11:00:00Z","stop":null,"duration":-1234567890},
          {"id":3,"start":"2026-03-10T12:00:00Z","stop":"2026-03-10T13:30:00Z","duration":5400}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let client = TogglClient(token: "tok", session: session)
        let tz = TimeZone(identifier: "UTC")!
        let start = makeDate("2026-03-10", tz: tz)
        let end   = makeDate("2026-03-11", tz: tz)
        let buckets = try await client.dailyTrackedHours(start: start, end: end, timeZone: tz)

        // Only entries 1 and 3 should count: 3600 + 5400 = 9000s = 2.5h
        XCTAssertEqual(try XCTUnwrap(buckets["2026-03-10"]), 2.5, accuracy: 1e-9)
        XCTAssertEqual(buckets.count, 1)
    }

    // MARK: - 4. 403 invalid token → validateToken returns false

    func testValidateTokenReturnsFalseOn403() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let client = TogglClient(token: "badtoken", session: session)
        let result = try await client.validateToken()
        XCTAssertFalse(result, "validateToken should return false on 403")
    }

    // MARK: - 5. Empty range returns empty map

    func testEmptyResponseReturnsEmptyMap() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "[]".data(using: .utf8)!)
        }

        let client = TogglClient(token: "tok", session: session)
        let tz = TimeZone(identifier: "UTC")!
        let start = makeDate("2026-01-01", tz: tz)
        let end   = makeDate("2026-01-02", tz: tz)
        let buckets = try await client.dailyTrackedHours(start: start, end: end, timeZone: tz)

        XCTAssertTrue(buckets.isEmpty, "Empty response array should produce empty bucket map")
    }

    // MARK: - 6. DST / timezone correctness (America/Los_Angeles spring-forward)

    func testDSTSpringForwardBucketingIsCorrect() async throws {
        // America/Los_Angeles springs forward 2026-03-08T02:00 → 03:00 (UTC-8 → UTC-7).
        // On that day the wall clock has only 23 hours. Entries should still bucket to
        // the correct local dateKey despite the timezone shift.
        //
        // Entry at 2026-03-08T01:30 UTC = 2026-03-07T17:30 PST  → "2026-03-07"
        // Entry at 2026-03-08T10:00 UTC = 2026-03-08T02:00 PDT  → "2026-03-08"
        let body = """
        [
          {"id":1,"start":"2026-03-08T01:30:00Z","stop":"2026-03-08T02:00:00Z","duration":1800},
          {"id":2,"start":"2026-03-08T10:00:00Z","stop":"2026-03-08T11:00:00Z","duration":3600}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let client = TogglClient(token: "tok", session: session)
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        let utcTZ = TimeZone(identifier: "UTC")!
        let start = makeDate("2026-03-07", tz: utcTZ)
        let end   = makeDate("2026-03-10", tz: utcTZ)
        let buckets = try await client.dailyTrackedHours(start: start, end: end, timeZone: tz)

        // Entry 1 at 01:30 UTC = 17:30 PST on March 7 → key "2026-03-07"
        XCTAssertEqual(try XCTUnwrap(buckets["2026-03-07"]), 1800.0 / 3600.0, accuracy: 1e-9,
                       "Entry before DST transition should bucket to 2026-03-07 in LA time")
        // Entry 2 at 10:00 UTC = 03:00 PDT on March 8 → key "2026-03-08"
        XCTAssertEqual(try XCTUnwrap(buckets["2026-03-08"]), 1.0, accuracy: 1e-9,
                       "Entry after DST transition should bucket to 2026-03-08 in LA time")
        XCTAssertEqual(buckets.count, 2)
    }

    // MARK: - 7. validateToken returns true on 200

    func testValidateTokenReturnsTrueOn200() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }

        let client = TogglClient(token: "goodtoken", session: session)
        let result = try await client.validateToken()
        XCTAssertTrue(result)
    }

    // MARK: - 8. 429 rate-limit error

    func testRateLimitedThrowsWithRetryAfter() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "60"]
            )!
            return (response, Data())
        }

        let client = TogglClient(token: "tok", session: session)
        let tz = TimeZone(identifier: "UTC")!
        let start = makeDate("2026-01-01", tz: tz)
        let end   = makeDate("2026-01-02", tz: tz)

        do {
            _ = try await client.dailyTrackedHours(start: start, end: end, timeZone: tz)
            XCTFail("Expected TogglError.rateLimited to be thrown")
        } catch TogglClient.TogglError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 60)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeDate(_ isoDay: String, tz: TimeZone) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = tz
        return f.date(from: isoDay)!
    }
}
