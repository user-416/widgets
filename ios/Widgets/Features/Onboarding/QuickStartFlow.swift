import Foundation
import SwiftData
import WidgetsShared

/// Zero-config "Quick Start" first-run flow. Requests HealthKit auth, creates
/// 3 default metrics (Steps + Workouts + Daily count), and triggers a snapshot
/// rebuild so the home grid has data within seconds. On HealthKit denial, only
/// the Manual metric is created and pre-seeded with two weeks of demo entries
/// so the empty state never feels empty.
@MainActor
struct QuickStartFlow {
    enum Outcome: Equatable {
        case healthKitConnected
        case manualOnly
    }

    let context: ModelContext
    let integrations: IntegrationContainer

    init(context: ModelContext, integrations: IntegrationContainer) {
        self.context = context
        self.integrations = integrations
    }

    func run() async -> Outcome {
        var healthKitGranted = false
        do {
            healthKitGranted = try await integrations.health.requestAuthorization()
        } catch {
            healthKitGranted = false
        }

        if healthKitGranted {
            insertHealthKitMetric(name: "Steps", kind: .healthkitSteps, color: .blue, sortOrder: 0)
            insertHealthKitMetric(name: "Workouts", kind: .healthkitWorkoutsMinutes, color: .orange, sortOrder: 1)
            insertManualMetric(name: "Daily count", color: .githubGreen, sortOrder: 2, seedDemo: false)
        } else {
            insertManualMetric(name: "Daily count", color: .githubGreen, sortOrder: 0, seedDemo: true)
        }

        try? context.save()
        await SyncCoordinator(context: context, integrations: integrations).rebuildSnapshot()
        return healthKitGranted ? .healthKitConnected : .manualOnly
    }

    private func insertHealthKitMetric(name: String, kind: MetricKind, color: PaletteName, sortOrder: Int) {
        let metric = PersistedMetric(name: name, kind: kind, color: color, sortOrder: sortOrder)
        context.insert(metric)
        BackfillQueue.enqueue(metricID: metric.id, daysBack: 365)
    }

    private func insertManualMetric(name: String, color: PaletteName, sortOrder: Int, seedDemo: Bool) {
        let metric = PersistedMetric(name: name, kind: .manual, color: color, sortOrder: sortOrder)
        context.insert(metric)
        guard seedDemo else { return }

        // Two weeks of light, varied counts so the heatmap doesn't read as empty
        // on a fresh install when HealthKit is denied. Deterministic so screenshots
        // are consistent — bd-07 will replace SampleData with similar logic.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = Date()
        let pattern: [Int] = [3, 2, 4, 1, 5, 0, 2, 3, 1, 4, 2, 3, 5, 1]
        for (offset, count) in pattern.enumerated() where count > 0 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let entry = PersistedManualEntry(
                metric: metric,
                dateKey: SnapshotMetric.dateKey(for: date),
                count: Double(count)
            )
            context.insert(entry)
        }
    }
}
