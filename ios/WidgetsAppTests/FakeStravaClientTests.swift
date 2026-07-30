// Unit tests for `FakeStravaClient`. Covers determinism, scenario
// behaviour (including the intentionally-asserted A3-4 expired-mid-
// paginate latent bug), and token minting/validation semantics.
//
// Mirrors `StravaClientTests` style. Runs in DEBUG only (the fake
// itself is `#if DEBUG`-gated).
import XCTest
import AuthenticationServices
@testable import Widgets

#if DEBUG
final class FakeStravaClientTests: XCTestCase {

    private func makeClient(_ scenario: FakeScenario.Strava = .happy) -> FakeStravaClient {
        FakeStravaClient(scenario: scenario, latency: 0...0)
    }

    private let utc = TimeZone(identifier: "UTC") ?? .current
    private let since = Date(timeIntervalSince1970: 1_745_625_600 - 90 * 86_400) // ~90 days before
    private let until = Date(timeIntervalSince1970: 1_745_798_400)

    override func setUp() {
        super.setUp()
        // Pin the persistent athlete id so `testDeterminismSameAthleteSameTotals`
        // sees a stable seed across test invocations. This also prevents
        // test ordering from making the assertion non-deterministic.
        UserDefaults.standard.removeObject(forKey: "debug.fakeStrava.athleteId")
        UserDefaults.standard.removeObject(forKey: "debug.fakeStrava.installId")
        UserDefaults.standard.set("test-install-id-fixed", forKey: "debug.fakeStrava.installId")
    }

    override func tearDown() {
        FakeStravaClient.resetPersistentAthlete()
        super.tearDown()
    }

    // MARK: - Determinism

    func testDeterminismSameAthleteSameTotals() async throws {
        let client = makeClient()
        let a = try await client.dailyActivityMinutes(accessToken: "fake_at_x", since: since, until: until, timeZone: utc)
        let b = try await client.dailyActivityMinutes(accessToken: "fake_at_x", since: since, until: until, timeZone: utc)
        XCTAssertEqual(a, b, "Same athlete id must yield identical buckets across calls")
        XCTAssertGreaterThan(a.count, 0, "Happy-path fake should generate some days")
    }

    // MARK: - Scenarios

    func testEmptyScenarioReturnsEmpty() async throws {
        let client = makeClient(.empty)
        let days = try await client.dailyActivityMinutes(accessToken: "fake_at", since: since, until: until, timeZone: utc)
        XCTAssertTrue(days.isEmpty)
    }

    func testRateLimitedScenarioThrowsRateLimited() async {
        let client = makeClient(.rateLimited)
        do {
            _ = try await client.dailyActivityMinutes(accessToken: "fake_at", since: since, until: until, timeZone: utc)
            XCTFail("Expected throw")
        } catch StravaClient.StravaError.rateLimited {
            // Pass — retryAfter alternates nil/600 by `since` parity.
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testExpiredMidPaginateThrows() async {
        // Latent bug A3-4: live `StravaClient` does NOT retry on a 401
        // returned mid-pagination — it just throws `invalidResponse`.
        // The fake faithfully reproduces this. When A3 lands, the live
        // client will retry and the fake will be flipped to no-throw,
        // and this assertion will be inverted. Until then, this PASSES
        // and serves as a fixture for the bug.
        let client = makeClient(.expiredMidPaginate)
        do {
            _ = try await client.dailyActivityMinutes(accessToken: "fake_at", since: since, until: until, timeZone: utc)
            XCTFail("Expected throw (asserts known A3-4 bug)")
        } catch StravaClient.StravaError.invalidResponse {
            // Expected — bug repro.
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testDeniedScenarioThrows() async {
        let client = makeClient(.denied)
        do {
            _ = try await client.dailyActivityMinutes(accessToken: "fake_at", since: since, until: until, timeZone: utc)
            XCTFail("Expected throw")
        } catch StravaClient.StravaError.oauthError(let msg) {
            XCTAssertEqual(msg, "access_denied")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - Auth half

    @MainActor
    func testAuthenticateMintsTokens() async throws {
        let client = makeClient()
        // ASPresentationAnchor isn't actually used by the fake (auth is
        // short-circuited) but we still need a value of the right type.
        let anchor = ASPresentationAnchor()
        let workerURL = URL(string: "https://example.workers.dev")!
        let tokens = try await client.authenticate(presentationAnchor: anchor, workerBaseURL: workerURL)
        XCTAssertTrue(tokens.accessToken.hasPrefix("fake_at_"), "Access token should be a fake-format token; got \(tokens.accessToken)")
        XCTAssertTrue(tokens.refreshToken.hasPrefix("fake_rt_"), "Refresh token should be a fake-format token; got \(tokens.refreshToken)")
        XCTAssertGreaterThan(tokens.expiresAt.timeIntervalSinceNow, 0, "Tokens should expire in the future")
    }

    func testRefreshValidatesPrefix() async {
        let client = makeClient()
        // A non-fake refresh token (e.g., a stale real token surviving a
        // fake-mode toggle) should be rejected — the fake should never
        // accidentally appear "authenticated" with a real token.
        do {
            _ = try await client.refresh(workerBaseURL: URL(string: "https://example.workers.dev")!, refreshToken: "real_rt_abc")
            XCTFail("Expected throw")
        } catch StravaClient.StravaError.oauthError(let msg) {
            XCTAssertEqual(msg, "invalid_refresh_token")
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        // A valid fake refresh token should succeed.
        do {
            let tokens = try await client.refresh(
                workerBaseURL: URL(string: "https://example.workers.dev")!,
                refreshToken: "fake_rt_12345"
            )
            XCTAssertEqual(tokens.refreshToken, "fake_rt_12345", "Refresh should reuse the supplied refresh token")
            XCTAssertTrue(tokens.accessToken.hasPrefix("fake_at_"))
        } catch {
            XCTFail("Valid fake refresh should not throw: \(error)")
        }
    }
}

#endif
