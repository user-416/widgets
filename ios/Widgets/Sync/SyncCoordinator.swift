import Foundation
import SwiftData
import WidgetsShared
import OSLog

@MainActor
struct SyncCoordinator {
    let context: ModelContext
    let integrations: IntegrationContainer

    init(context: ModelContext, integrations: IntegrationContainer) {
        self.context = context
        self.integrations = integrations
    }

    private static let logger = Logger(subsystem: "io.github.user-416.widgets", category: "Sync")

    /// Rebuilds the App Group snapshot from local SwiftData state plus remote/HealthKit data.
    /// Network calls happen off the main actor; SwiftData reads/writes stay on it.
    func rebuildSnapshot(now: Date = .now) async {
        let descriptor = FetchDescriptor<PersistedMetric>(
            predicate: #Predicate { !$0.archived },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        let persisted = (try? context.fetch(descriptor)) ?? []

        var snapshotMetrics: [SnapshotMetric] = []
        for metric in persisted {
            let days = await collectDays(for: metric)
            snapshotMetrics.append(SnapshotMetric(
                id: metric.id,
                name: metric.name,
                kind: metric.kind,
                color: metric.color,
                thresholds: metric.thresholds,
                days: days
            ))
        }

        let snapshot = Snapshot(generatedAt: now, metrics: snapshotMetrics)
        SnapshotWriter.write(snapshot)
    }

    /// Cheap rebuild — only updates manual entries, no network calls.
    /// Used after a tap-to-increment so the widget reloads instantly.
    func rebuildManualOnly() {
        let descriptor = FetchDescriptor<PersistedMetric>(
            predicate: #Predicate { !$0.archived },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        let persisted = (try? context.fetch(descriptor)) ?? []

        let existing = SnapshotWriter.read()
        let existingByID = Dictionary(uniqueKeysWithValues: existing.metrics.map { ($0.id, $0) })

        let snapshotMetrics: [SnapshotMetric] = persisted.map { metric in
            let kind = metric.kind
            if kind == .manual {
                var days: [String: Double] = [:]
                for entry in metric.manualEntries {
                    days[entry.dateKey, default: 0] += entry.count
                }
                return SnapshotMetric(
                    id: metric.id,
                    name: metric.name,
                    kind: kind,
                    color: metric.color,
                    thresholds: metric.thresholds,
                    days: days
                )
            } else if let cached = existingByID[metric.id] {
                return SnapshotMetric(
                    id: metric.id,
                    name: metric.name,
                    kind: kind,
                    color: metric.color,
                    thresholds: metric.thresholds,
                    days: cached.days
                )
            } else {
                return SnapshotMetric(
                    id: metric.id,
                    name: metric.name,
                    kind: kind,
                    color: metric.color,
                    thresholds: metric.thresholds,
                    days: [:]
                )
            }
        }

        SnapshotWriter.write(Snapshot(generatedAt: .now, metrics: snapshotMetrics))
    }

    private func collectDays(for metric: PersistedMetric) async -> [String: Double] {
        switch metric.kind {
        case .manual:
            var days: [String: Double] = [:]
            for entry in metric.manualEntries {
                days[entry.dateKey, default: 0] += entry.count
            }
            return days

        case .healthkitSteps:
            do {
                return try await integrations.health.dailySteps(
                    daysBack: 365,
                    endDate: .now,
                    timeZone: .current
                )
            } catch {
                Self.logger.error("HealthKit steps failed: \(error.localizedDescription)")
                return cachedDays(for: metric)
            }

        case .healthkitWorkoutsMinutes:
            do {
                return try await integrations.health.dailyWorkoutMinutes(
                    daysBack: 365,
                    endDate: .now,
                    timeZone: .current
                )
            } catch {
                Self.logger.error("HealthKit workouts failed: \(error.localizedDescription)")
                return cachedDays(for: metric)
            }

        case .healthkitSleep:
            do {
                return try await integrations.health.dailySleep(
                    daysBack: 365,
                    endDate: .now,
                    timeZone: .current
                )
            } catch {
                Self.logger.error("HealthKit sleep failed: \(error.localizedDescription)")
                return cachedDays(for: metric)
            }

        case .healthkitActiveEnergy:
            do {
                return try await integrations.health.dailyActiveEnergy(
                    daysBack: 365,
                    endDate: .now,
                    timeZone: .current
                )
            } catch {
                Self.logger.error("HealthKit active energy failed: \(error.localizedDescription)")
                return cachedDays(for: metric)
            }

        case .healthkitMindfulMinutes:
            do {
                return try await integrations.health.dailyMindfulMinutes(
                    daysBack: 365,
                    endDate: .now,
                    timeZone: .current
                )
            } catch {
                Self.logger.error("HealthKit mindful minutes failed: \(error.localizedDescription)")
                return cachedDays(for: metric)
            }

        case .healthkitHRV:
            do {
                return try await integrations.health.dailyHRV(
                    daysBack: 365,
                    endDate: .now,
                    timeZone: .current
                )
            } catch {
                Self.logger.error("HealthKit HRV failed: \(error.localizedDescription)")
                return cachedDays(for: metric)
            }

        case .healthkitRestingHR:
            do {
                return try await integrations.health.dailyRestingHR(
                    daysBack: 365,
                    endDate: .now,
                    timeZone: .current
                )
            } catch {
                Self.logger.error("HealthKit resting HR failed: \(error.localizedDescription)")
                return cachedDays(for: metric)
            }

        case .healthkitBodyMass:
            do {
                return try await integrations.health.dailyBodyMass(
                    daysBack: 365,
                    endDate: .now,
                    timeZone: .current
                )
            } catch {
                Self.logger.error("HealthKit body mass failed: \(error.localizedDescription)")
                return cachedDays(for: metric)
            }

        case .stravaActivityMinutes:
            return await collectStravaDays(for: metric)

        case .togglTrackedHours:
            do {
                let since = Date().addingTimeInterval(-365 * 86_400)
                return try await integrations.toggl.dailyTrackedHours(
                    start: since,
                    end: .now,
                    timeZone: .current
                )
            } catch {
                Self.logger.error("Toggl sync failed: \(error.localizedDescription)")
                return cachedDays(for: metric)
            }
        }
    }

    private static let stravaCooldownKey = "strava.cooldownUntil"

    private func collectStravaDays(for metric: PersistedMetric) async -> [String: Double] {
        if let cooldownUntil = UserDefaults.standard.object(forKey: Self.stravaCooldownKey) as? Date,
           cooldownUntil > .now {
            Self.logger.notice("Strava cooldown active until \(cooldownUntil)")
            return cachedDays(for: metric)
        }

        guard var tokens = IntegrationCredentials.Strava.tokens() else {
            Self.logger.notice("No Strava tokens; skipping strava metric \(metric.id)")
            return cachedDays(for: metric)
        }

        // Refresh ~5 min before expiry.
        if tokens.expiresAt.timeIntervalSinceNow < 300 {
            guard let workerURL = Configuration.workerBaseURL else {
                Self.logger.notice("Strava worker URL not configured; serving cached days")
                return cachedDays(for: metric)
            }
            do {
                let refreshed = try await integrations.strava.refresh(
                    workerBaseURL: workerURL,
                    refreshToken: tokens.refreshToken
                )
                try IntegrationCredentials.Strava.store(refreshed)
                tokens = refreshed
            } catch {
                Self.logger.error("Strava refresh failed: \(error.localizedDescription)")
                return cachedDays(for: metric)
            }
        }

        var merged = cachedDays(for: metric)

        // Process pending backfill chunk if any (~7 days, jittered would be ideal).
        if let chunk = BackfillQueue.nextChunk(metricID: metric.id) {
            // Build a refresh closure StravaClient can use if it hits a 401
            // mid-pagination (page N succeeds, page N+1 401s after the access
            // token expires). Without this, the partial work on pages 1..N is
            // lost and the chunk has to start over.
            let strava = integrations.strava
            let refresh: @Sendable () async throws -> String = {
                guard let workerURL = Configuration.stravaWorkerBaseURL,
                      let stored = IntegrationCredentials.Strava.tokens() else {
                    throw StravaClient.StravaError.invalidResponse
                }
                let refreshed = try await strava.refresh(
                    workerBaseURL: workerURL,
                    refreshToken: stored.refreshToken
                )
                try IntegrationCredentials.Strava.store(refreshed)
                return refreshed.accessToken
            }
            do {
                let chunkDays = try await integrations.strava.dailyActivityMinutes(
                    accessToken: tokens.accessToken,
                    since: chunk.start,
                    until: chunk.end,
                    timeZone: .current,
                    refreshAccessToken: refresh
                )
                for (k, v) in chunkDays { merged[k] = v }
                BackfillQueue.markChunkComplete(metricID: metric.id, end: chunk.end)
            } catch StravaClient.StravaError.rateLimited(let retryAfter) {
                let wait = retryAfter ?? 600
                let until = Date().addingTimeInterval(wait)
                UserDefaults.standard.set(until, forKey: Self.stravaCooldownKey)
                SharedSettings.lastStravaRateLimit = until
                Self.logger.notice("Strava 429; cooldown until \(until)")
                return merged
            } catch {
                Self.logger.error("Strava backfill failed: \(error.localizedDescription)")
                return merged
            }
        }

        // Also poll the last 2 days to keep today/yesterday fresh.
        do {
            let recent = try await integrations.strava.dailyActivityMinutes(
                accessToken: tokens.accessToken,
                since: Date().addingTimeInterval(-2 * 86_400),
                until: .now,
                timeZone: .current
            )
            for (k, v) in recent { merged[k] = v }
            // Successful poll — clear any stale cooldown surface.
            if let until = SharedSettings.lastStravaRateLimit, until <= .now {
                SharedSettings.lastStravaRateLimit = nil
            }
        } catch StravaClient.StravaError.rateLimited(let retryAfter) {
            let wait = retryAfter ?? 600
            let until = Date().addingTimeInterval(wait)
            UserDefaults.standard.set(until, forKey: Self.stravaCooldownKey)
            SharedSettings.lastStravaRateLimit = until
            Self.logger.notice("Strava 429 on recent poll; cooldown until \(until)")
        } catch {
            Self.logger.error("Strava recent poll failed: \(error.localizedDescription)")
        }

        return merged
    }

    private func cachedDays(for metric: PersistedMetric) -> [String: Double] {
        let snapshot = SnapshotWriter.read()
        return snapshot.metrics.first(where: { $0.id == metric.id })?.days ?? [:]
    }
}
