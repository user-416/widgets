// Integration tests that wire `FakeStravaClient` / `FakeHealthClient`
// together through `IntegrationContainer.fake` and drive the live
// `SyncCoordinator.rebuildSnapshot()`.
//
// Asserts the full pipeline: PersistedMetric → fake client → snapshot
// shape. Skeleton from `.context/orchestrator/runs/B4-fake-mode-design.md`
// §8.
//
// Notes:
//   - Tests run on the host app, so App Group entitlement is available
//     and `SnapshotWriter` actually persists to disk.
//   - Strava path needs Keychain tokens. They are seeded in `setUp` and
//     torn down in `tearDown` to avoid leaking across tests / runs.
//   - Each test uses an in-memory `ModelContainer` so SwiftData state
//     doesn't leak.
import XCTest
import SwiftData
import WidgetsShared
@testable import Widgets

#if DEBUG
@MainActor
final class SyncCoordinatorIntegrationTests: XCTestCase {

    private var modelContainer: ModelContainer!
    private var context: ModelContext!

    // Static IDs so we can find them in the snapshot after a rebuild.
    private let stravaID = "test-strava-activity"
    private let healthID = "test-healthkit-steps"

    /// Set to false in setUp() if Keychain isn't available (e.g.,
    /// CODE_SIGNING_ALLOWED=NO strips the keychain entitlement so
    /// SecItemAdd fails with -34018 errSecMissingEntitlement). Tests
    /// that exercise the Strava credential paths use
    /// `try XCTSkipUnless(keychainAvailable)` so the suite still runs
    /// the parts that don't need it.
    private var keychainAvailable = false

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([PersistedMetric.self, PersistedManualEntry.self])
        modelContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = ModelContext(modelContainer)

        // Seed credentials so SyncCoordinator's gating logic doesn't
        // skip the integrations. If the keychain entitlement isn't
        // present (common with CODE_SIGNING_ALLOWED=NO), flag tests
        // for skip rather than failing.
        do {
            try IntegrationCredentials.Strava.store(StravaTokens(
                accessToken: "fake_at_seed_0",
                refreshToken: "fake_rt_seed_0",
                expiresAt: Date(timeIntervalSinceNow: 6 * 3600),
                athleteId: 99_888_777
            ))
            keychainAvailable = true
        } catch {
            keychainAvailable = false
        }

        // Reset Strava cooldown / backfill state from prior runs.
        UserDefaults.standard.removeObject(forKey: "strava.cooldownUntil")
        BackfillQueue.clear(metricID: stravaID)

        // Pin the fake-strava install id for stability.
        UserDefaults.standard.removeObject(forKey: "debug.fakeStrava.athleteId")
        UserDefaults.standard.set("integration-test-install", forKey: "debug.fakeStrava.installId")
    }

    override func tearDown() async throws {
        try? IntegrationCredentials.Strava.disconnect()
        UserDefaults.standard.removeObject(forKey: "strava.cooldownUntil")
        BackfillQueue.clear(metricID: stravaID)
        FakeStravaClient.resetPersistentAthlete()
        modelContainer = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func seedTwoMetrics() {
        context.insert(PersistedMetric(id: healthID, name: "Steps", kind: .healthkitSteps, sortOrder: 0))
        context.insert(PersistedMetric(id: stravaID, name: "Strava", kind: .stravaActivityMinutes, sortOrder: 1))
        try? context.save()
    }

    private func zeroLatencyContainer(
        strava: FakeScenario.Strava = .happy,
        health: FakeScenario.Health = .happy
    ) -> IntegrationContainer {
        IntegrationContainer(
            strava: FakeStravaClient(scenario: strava, latency: 0...0),
            health: FakeHealthClient(scenario: health),
            toggl: LiveTogglClient()
        )
    }

    // MARK: - Tests

    func testFakeContainerProducesShapedSnapshot() async throws {
        // SyncCoordinator persists via SnapshotWriter, which writes to
        // the App Group container. CODE_SIGNING_ALLOWED=NO strips the
        // entitlement, so the write is a silent no-op and SnapshotWriter
        // .read() returns .empty. Skip the assertion in that case but
        // still exercise the build/wire path so the file compiles.
        try XCTSkipUnless(AppGroup.containerURL != nil, "App Group container unavailable; SnapshotWriter is a no-op without entitlements")

        seedTwoMetrics()

        let coordinator = SyncCoordinator(
            context: context,
            integrations: zeroLatencyContainer()
        )
        await coordinator.rebuildSnapshot()

        let snapshot = SnapshotWriter.read()
        XCTAssertEqual(snapshot.metrics.count, 2, "Both metrics should be in the snapshot")

        let byID = Dictionary(uniqueKeysWithValues: snapshot.metrics.map { ($0.id, $0) })
        let health = try XCTUnwrap(byID[healthID])

        // Health steps: 180-day window, recipe-driven. No Keychain
        // dependency, so this assertion runs everywhere.
        XCTAssertGreaterThan(health.days.count, 100, "Health steps fake should produce >100 days; got \(health.days.count)")
        XCTAssertTrue(health.days.values.allSatisfy { $0 >= 0 && $0 < 30_000 }, "Step counts should be in plausible range")
        XCTAssertTrue(health.days.values.contains { $0 > 3_000 }, "Steps recipe should produce realistic counts")

        // Strava requires Keychain credentials (read by SyncCoordinator
        // before invoking the fake). Skip the assertion when running
        // with a stripped keychain entitlement.
        try XCTSkipUnless(keychainAvailable, "Keychain entitlement unavailable; Strava assertions skipped")

        let strava = try XCTUnwrap(byID[stravaID])

        // Strava: SyncCoordinator only polls last 2 days for non-backfill,
        // so the snapshot has at most a couple of days unless we ran a
        // backfill chunk. Either way, days should never have negative
        // values, and any present values should be in plausible minute
        // ranges.
        XCTAssertTrue(strava.days.values.allSatisfy { $0 >= 0 && $0 < 24 * 60 * 2 }, "Strava minutes should be in plausible range")
    }

    func testStravaUserDeniedSurfacesError() async {
        // The fake's `.denied` scenario throws `oauthError("access_denied")`.
        // SyncCoordinator catches this and falls back to cached days, so
        // the user-visible snapshot won't surface the error directly.
        // We assert at the protocol boundary that the fake propagates
        // the expected error type — that's the contract the rest of the
        // app (and any future error-bubbling work in A3) depends on.
        let denied = FakeStravaClient(scenario: .denied, latency: 0...0)
        let until = Date(timeIntervalSince1970: 1_745_798_400)
        let since = until.addingTimeInterval(-90 * 86_400)

        do {
            _ = try await denied.dailyActivityMinutes(
                accessToken: "fake_at_seed",
                since: since,
                until: until,
                timeZone: TimeZone(identifier: "UTC") ?? .current
            )
            XCTFail("Expected denied scenario to throw")
        } catch StravaClient.StravaError.oauthError(let msg) {
            XCTAssertEqual(msg, "access_denied", "Denied scenario must surface access_denied")
        } catch {
            XCTFail("Wrong error type from .denied scenario: \(error)")
        }
    }
}
#endif
