#if DEBUG
import Foundation
import HealthKit
import OSLog

enum HealthKitDebug {
    private static let logger = Logger(subsystem: "io.github.user-416.widgets", category: "HealthKitDebug")
    private static let store = HKHealthStore()

    /// Writes ~90 days of fake step samples with realistic per-day variance so the
    /// HealthKit metric flow is testable in the iOS Simulator (which has no real
    /// step data). Requires write permission on first call.
    static func injectSampleSteps(daysBack: Int = 90, calendar: Calendar = .current) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit not available")
            return
        }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            logger.error("No step quantity type")
            return
        }
        do {
            try await store.requestAuthorization(toShare: [stepType], read: [stepType])
        } catch {
            logger.error("Authorization failed: \(error.localizedDescription)")
            return
        }

        var cal = calendar
        cal.timeZone = .current
        let today = Date()

        var samples: [HKQuantitySample] = []
        for offset in 0..<daysBack {
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: today)),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let count = Double(Int.random(in: 0...18_000))
            guard count > 0 else { continue }
            let quantity = HKQuantity(unit: .count(), doubleValue: count)
            let sample = HKQuantitySample(
                type: stepType,
                quantity: quantity,
                start: dayStart,
                end: dayEnd
            )
            samples.append(sample)
        }

        do {
            try await store.save(samples)
            logger.info("Injected \(samples.count) fake step samples")
        } catch {
            logger.error("Failed to save samples: \(error.localizedDescription)")
        }
    }
}
#endif
