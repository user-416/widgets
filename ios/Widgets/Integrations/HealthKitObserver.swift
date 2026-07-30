import Foundation
import HealthKit
import OSLog

// Background delivery is a no-op in the iOS Simulator; HealthKit only fires
// HKObserverQuery updates from real devices. Test on hardware.
// `activeQueries` is only mutated from the app's main thread (start/stop are UI-driven),
// so unchecked Sendable is safe here. HKHealthStore is itself thread-safe.
final class HealthKitObserver: @unchecked Sendable {
    private let logger = Logger(subsystem: "io.github.user-416.widgets", category: "HealthKit")
    private let store = HKHealthStore()
    private var activeQueries: [HKObserverQuery] = []

    func start(onChange: @escaping @Sendable () -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.notice("HealthKit unavailable; observer not started")
            return
        }

        var types: [HKSampleType] = [HKWorkoutType.workoutType()]
        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.append(stepType)
        }

        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                if let error {
                    self?.logger.error("Observer query error for \(type.identifier): \(error.localizedDescription)")
                    completionHandler()
                    return
                }
                self?.logger.info("Observer fired for \(type.identifier)")
                onChange()
                completionHandler()
            }
            store.execute(query)
            activeQueries.append(query)

            store.enableBackgroundDelivery(for: type, frequency: .immediate) { [weak self] success, error in
                if let error {
                    self?.logger.error("Background delivery failed for \(type.identifier): \(error.localizedDescription)")
                } else {
                    self?.logger.info("Background delivery enabled for \(type.identifier): \(success)")
                }
            }
        }
    }

    func stop() {
        for query in activeQueries {
            store.stop(query)
        }
        activeQueries.removeAll()
        store.disableAllBackgroundDelivery { [weak self] _, error in
            if let error {
                self?.logger.error("Disable background delivery failed: \(error.localizedDescription)")
            }
        }
    }
}
