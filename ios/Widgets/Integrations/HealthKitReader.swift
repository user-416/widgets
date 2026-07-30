import Foundation
import WidgetsShared
import HealthKit
import OSLog

enum HealthKitError: Error {
    case notAvailable
    case authorizationDenied
    case queryFailed(any Error)
}

enum HealthKitReader {
    private static let logger = Logger(subsystem: "io.github.user-416.widgets", category: "HealthKit")
    private static let store = HKHealthStore()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    static func requestAuthorization() async throws -> Bool {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
              let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitError.notAvailable
        }
        let workoutType = HKWorkoutType.workoutType()
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession)!

        let readTypes: Set<HKObjectType> = [
            stepType,
            workoutType,
            sleepType,
            activeEnergyType,
            mindfulType,
            hrvType,
            restingHRType,
            bodyMassType,
        ]

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            logger.error("Authorization request failed: \(error.localizedDescription)")
            throw HealthKitError.queryFailed(error)
        }

        // HealthKit deliberately hides read-permission status to prevent leakage,
        // so we treat a non-throwing request as success and let queries return zero data
        // when permission was actually denied.
        return true
    }

    static func dailySteps(
        daysBack: Int = 365,
        endDate: Date = .now,
        timeZone: TimeZone = .current
    ) async throws -> [String: Double] {
        guard isAvailable else { throw HealthKitError.notAvailable }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.notAvailable
        }

        return try await dailyCumulativeSum(
            quantityType: stepType,
            unit: .count(),
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    static func dailyWorkoutMinutes(
        daysBack: Int = 365,
        endDate: Date = .now,
        timeZone: TimeZone = .current
    ) async throws -> [String: Double] {
        guard isAvailable else { throw HealthKitError.notAvailable }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let endOfDay = calendar.startOfDay(for: endDate)
        guard let anchor = calendar.date(byAdding: .day, value: -(daysBack - 1), to: endOfDay),
              let queryEnd = calendar.date(byAdding: .day, value: 1, to: endOfDay) else {
            return [:]
        }

        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: queryEnd, options: .strictStartDate)
        let workoutType = HKWorkoutType.workoutType()

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    Self.logger.error("Workout query failed: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [:])
                    return
                }
                var bucket: [String: Double] = [:]
                for workout in workouts {
                    let key = SnapshotMetric.dateKey(for: workout.startDate, timeZone: timeZone)
                    let minutes = workout.duration / 60.0
                    bucket[key, default: 0] += minutes
                }
                Self.logger.info("Fetched workouts for \(bucket.count) day(s) from \(workouts.count) sample(s)")
                continuation.resume(returning: bucket)
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep

    /// Returns total asleep minutes per day, attributed to the **wake-up day** (the calendar day
    /// on which the session ends). This matches what the Apple Health app displays: a 23:30–07:15
    /// cross-midnight session shows all 465 minutes on the morning wake-up day, not split across
    /// two days. Convention: wake-up-day attribution. See PR description for rationale.
    ///
    /// Filters to asleep variants only (unspecified/core/deep/REM). Excludes `.inBed` and `.awake`.
    static func dailySleep(
        daysBack: Int = 365,
        endDate: Date = .now,
        timeZone: TimeZone = .current
    ) async throws -> [String: Double] {
        guard isAvailable else { throw HealthKitError.notAvailable }
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.notAvailable
        }

        return try await dailyCategorySessionMinutes(
            categoryType: sleepType,
            asleepFilter: true,
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    // MARK: - Active Energy

    static func dailyActiveEnergy(
        daysBack: Int = 365,
        endDate: Date = .now,
        timeZone: TimeZone = .current
    ) async throws -> [String: Double] {
        guard isAvailable else { throw HealthKitError.notAvailable }
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.notAvailable
        }
        return try await dailyCumulativeSum(
            quantityType: type,
            unit: .kilocalorie(),
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    // MARK: - Mindful Minutes

    /// Returns total mindful session minutes per day, attributed to the **wake-up day** (session
    /// end date) using the same convention as sleep. Cross-midnight sessions are bucketed to the
    /// day on which the session ends.
    static func dailyMindfulMinutes(
        daysBack: Int = 365,
        endDate: Date = .now,
        timeZone: TimeZone = .current
    ) async throws -> [String: Double] {
        guard isAvailable else { throw HealthKitError.notAvailable }
        guard let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else {
            throw HealthKitError.notAvailable
        }

        return try await dailyCategorySessionMinutes(
            categoryType: mindfulType,
            asleepFilter: false,
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    // MARK: - HRV

    /// Returns the discrete average HRV (in milliseconds) per day.
    static func dailyHRV(
        daysBack: Int = 365,
        endDate: Date = .now,
        timeZone: TimeZone = .current
    ) async throws -> [String: Double] {
        guard isAvailable else { throw HealthKitError.notAvailable }
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.notAvailable
        }
        // HRV is stored in seconds; convert to milliseconds.
        let unit = HKUnit.secondUnit(with: .milli)
        return try await dailyDiscreteAverage(
            quantityType: type,
            unit: unit,
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    // MARK: - Resting Heart Rate

    /// Returns the discrete average resting heart rate (BPM) per day.
    static func dailyRestingHR(
        daysBack: Int = 365,
        endDate: Date = .now,
        timeZone: TimeZone = .current
    ) async throws -> [String: Double] {
        guard isAvailable else { throw HealthKitError.notAvailable }
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw HealthKitError.notAvailable
        }
        // BPM = count / minute
        let unit = HKUnit.count().unitDivided(by: .minute())
        return try await dailyDiscreteAverage(
            quantityType: type,
            unit: unit,
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    // MARK: - Body Mass

    /// Returns the most recent body mass reading per day, in kilograms.
    static func dailyBodyMass(
        daysBack: Int = 365,
        endDate: Date = .now,
        timeZone: TimeZone = .current
    ) async throws -> [String: Double] {
        guard isAvailable else { throw HealthKitError.notAvailable }
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitError.notAvailable
        }
        return try await dailyLatest(
            quantityType: type,
            unit: .gramUnit(with: .kilo),
            daysBack: daysBack,
            endDate: endDate,
            timeZone: timeZone
        )
    }

    // MARK: - Internal helpers

    /// Cumulative sum per day via HKStatisticsCollectionQuery.
    private static func dailyCumulativeSum(
        quantityType: HKQuantityType,
        unit: HKUnit,
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let endOfDay = calendar.startOfDay(for: endDate)
        guard let anchor = calendar.date(byAdding: .day, value: -(daysBack - 1), to: endOfDay),
              let queryEnd = calendar.date(byAdding: .day, value: 1, to: endOfDay) else {
            return [:]
        }

        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: queryEnd, options: .strictStartDate)
        let interval = DateComponents(day: 1)

        let query = HKStatisticsCollectionQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: interval
        )

        return try await withCheckedThrowingContinuation { continuation in
            query.initialResultsHandler = { _, results, error in
                if let error {
                    Self.logger.error("Cumulative sum query failed: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                guard let results else {
                    continuation.resume(returning: [:])
                    return
                }
                var bucket: [String: Double] = [:]
                results.enumerateStatistics(from: anchor, to: queryEnd) { stats, _ in
                    let key = SnapshotMetric.dateKey(for: stats.startDate, timeZone: timeZone)
                    let value = stats.sumQuantity()?.doubleValue(for: unit) ?? 0
                    if value > 0 {
                        bucket[key] = value
                    }
                }
                continuation.resume(returning: bucket)
            }
            store.execute(query)
        }
    }

    /// Discrete average per day via HKStatisticsCollectionQuery.
    private static func dailyDiscreteAverage(
        quantityType: HKQuantityType,
        unit: HKUnit,
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let endOfDay = calendar.startOfDay(for: endDate)
        guard let anchor = calendar.date(byAdding: .day, value: -(daysBack - 1), to: endOfDay),
              let queryEnd = calendar.date(byAdding: .day, value: 1, to: endOfDay) else {
            return [:]
        }

        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: queryEnd, options: .strictStartDate)
        let interval = DateComponents(day: 1)

        let query = HKStatisticsCollectionQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .discreteAverage,
            anchorDate: anchor,
            intervalComponents: interval
        )

        return try await withCheckedThrowingContinuation { continuation in
            query.initialResultsHandler = { _, results, error in
                if let error {
                    Self.logger.error("Discrete average query failed: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                guard let results else {
                    continuation.resume(returning: [:])
                    return
                }
                var bucket: [String: Double] = [:]
                results.enumerateStatistics(from: anchor, to: queryEnd) { stats, _ in
                    let key = SnapshotMetric.dateKey(for: stats.startDate, timeZone: timeZone)
                    if let value = stats.averageQuantity()?.doubleValue(for: unit), value > 0 {
                        bucket[key] = value
                    }
                }
                continuation.resume(returning: bucket)
            }
            store.execute(query)
        }
    }

    /// Most-recent value per day via HKStatisticsCollectionQuery with .discreteMostRecent.
    private static func dailyLatest(
        quantityType: HKQuantityType,
        unit: HKUnit,
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let endOfDay = calendar.startOfDay(for: endDate)
        guard let anchor = calendar.date(byAdding: .day, value: -(daysBack - 1), to: endOfDay),
              let queryEnd = calendar.date(byAdding: .day, value: 1, to: endOfDay) else {
            return [:]
        }

        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: queryEnd, options: .strictStartDate)
        let interval = DateComponents(day: 1)

        let query = HKStatisticsCollectionQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .discreteMostRecent,
            anchorDate: anchor,
            intervalComponents: interval
        )

        return try await withCheckedThrowingContinuation { continuation in
            query.initialResultsHandler = { _, results, error in
                if let error {
                    Self.logger.error("Discrete most-recent query failed: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                guard let results else {
                    continuation.resume(returning: [:])
                    return
                }
                var bucket: [String: Double] = [:]
                results.enumerateStatistics(from: anchor, to: queryEnd) { stats, _ in
                    let key = SnapshotMetric.dateKey(for: stats.startDate, timeZone: timeZone)
                    if let value = stats.mostRecentQuantity()?.doubleValue(for: unit), value > 0 {
                        bucket[key] = value
                    }
                }
                continuation.resume(returning: bucket)
            }
            store.execute(query)
        }
    }

    /// Fetches HKCategorySample sessions and sums their duration in minutes,
    /// attributed to the **wake-up day** (the calendar day on which the session ends).
    ///
    /// - Parameters:
    ///   - asleepFilter: When true, only include samples whose value corresponds to an
    ///     "asleep" state (unspecified, core, deep, REM). When false (e.g. mindful sessions),
    ///     all samples are included regardless of value.
    static func dailyCategorySessionMinutes(
        categoryType: HKCategoryType,
        asleepFilter: Bool,
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let endOfDay = calendar.startOfDay(for: endDate)
        guard let anchor = calendar.date(byAdding: .day, value: -(daysBack - 1), to: endOfDay),
              let queryEnd = calendar.date(byAdding: .day, value: 1, to: endOfDay) else {
            return [:]
        }

        // Expand window by 1 day on each side to capture cross-midnight sessions
        // whose start is just before the window.
        guard let expandedStart = calendar.date(byAdding: .day, value: -1, to: anchor),
              let expandedEnd = calendar.date(byAdding: .day, value: 1, to: queryEnd) else {
            return [:]
        }

        let predicate = HKQuery.predicateForSamples(withStart: expandedStart, end: expandedEnd, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    Self.logger.error("Category session query failed: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                guard let categorySamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [:])
                    return
                }

                // Sleep-asleep values per HealthKit docs.
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]

                var bucket: [String: Double] = [:]

                for sample in categorySamples {
                    // Filter out non-asleep states when requested (sleep type only).
                    if asleepFilter && !asleepValues.contains(sample.value) {
                        continue
                    }

                    // Attribution: all minutes go to the wake-up day (endDate's calendar day).
                    // This matches what Apple Health shows: a 23:30–07:15 session is reported
                    // on the morning you wake up, not split across two days.
                    let wakeDay = calendar.startOfDay(for: sample.endDate)
                    let wakeKey = SnapshotMetric.dateKey(for: wakeDay, timeZone: timeZone)

                    // Only include sessions that fall within our requested window.
                    guard wakeDay >= anchor && wakeDay < queryEnd else { continue }

                    let totalMinutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    bucket[wakeKey, default: 0] += totalMinutes
                }

                Self.logger.info("Fetched category sessions for \(bucket.count) day(s) from \(categorySamples.count) sample(s)")
                continuation.resume(returning: bucket)
            }
            store.execute(query)
        }
    }
}
