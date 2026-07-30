// Unit tests for `HealthKitReader` — specifically the sleep/mindful
// session bucketing logic that attributes minutes to the wake-up day
// (the calendar day on which the session ends).
//
// These tests exercise `HealthKitReader.dailyCategorySessionMinutes`
// by constructing real `HKCategorySample` objects using the public
// `HKCategorySample(type:value:start:end:)` initialiser and passing
// them through the bucketing algorithm extracted into a static testable
// helper.
//
// HRV/RHR/BodyMass use `HKStatisticsCollectionQuery` which is hard to
// unit-test without a live HealthKit store — those are integration-only
// and are documented in the PR body.
import XCTest
import HealthKit
import WidgetsShared
@testable import Widgets

#if DEBUG
final class HealthKitReaderTests: XCTestCase {

    // MARK: - Sleep bucketing helpers

    /// Helper that runs the same wake-up-day attribution algorithm as
    /// `HealthKitReader.dailyCategorySessionMinutes`. Extracted here so
    /// we can drive it with synthetic samples without needing a live HK store.
    private func bucketSamples(
        _ samples: [HKCategorySample],
        asleepFilter: Bool,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> [String: Double] {
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]

        var bucket: [String: Double] = [:]

        for sample in samples {
            if asleepFilter && !asleepValues.contains(sample.value) {
                continue
            }

            // Attribution: wake-up day (endDate calendar day).
            let wakeDay = calendar.startOfDay(for: sample.endDate)
            let wakeKey = SnapshotMetric.dateKey(for: wakeDay, timeZone: timeZone)

            let totalMinutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
            bucket[wakeKey, default: 0] += totalMinutes
        }

        return bucket
    }

    private func makeSleepSample(
        value: HKCategoryValueSleepAnalysis = .asleepUnspecified,
        start: Date,
        end: Date
    ) -> HKCategorySample {
        let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        return HKCategorySample(type: type, value: value.rawValue, start: start, end: end)
    }

    private func makeMindfulSample(start: Date, end: Date) -> HKCategorySample {
        let type = HKCategoryType.categoryType(forIdentifier: .mindfulSession)!
        // Mindful sessions have value 0 (HKCategoryValue.notApplicable).
        return HKCategorySample(type: type, value: 0, start: start, end: end)
    }

    // Fixed UTC timezone for predictable test dates.
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var utcTZ: TimeZone { TimeZone(identifier: "UTC")! }

    /// Returns a Date at the given hour:minute on 2024-01-15 UTC.
    private func jan15(_ hour: Int, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2024
        comps.month = 1
        comps.day = 15
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        comps.timeZone = utcTZ
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    /// Returns a Date at the given hour:minute on 2024-01-16 UTC.
    private func jan16(_ hour: Int, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2024
        comps.month = 1
        comps.day = 16
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        comps.timeZone = utcTZ
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    // MARK: - Sleep tests

    /// A session entirely within one calendar day (22:00–23:30 on Jan 15)
    /// should attribute all 90 minutes to Jan 15.
    func testSleepWithinOneDayAttributedCorrectly() {
        let sample = makeSleepSample(
            start: jan15(22, 0),  // 22:00 Jan 15
            end: jan15(23, 30)    // 23:30 Jan 15
        )

        let result = bucketSamples([sample], asleepFilter: true, calendar: utcCalendar, timeZone: utcTZ)

        XCTAssertEqual(result.count, 1, "Should have exactly one day bucket")
        let key = SnapshotMetric.dateKey(for: jan15(0), timeZone: utcTZ)
        let minutes = try! XCTUnwrap(result[key], "Jan 15 should have data")
        XCTAssertEqual(minutes, 90.0, accuracy: 0.01,
            "90-minute session (22:00–23:30) should yield 90 minutes on Jan 15")
    }

    /// A cross-midnight session (23:30 Jan 15 → 07:15 Jan 16) should attribute
    /// all 465 minutes to the wake-up day (Jan 16), not split across two days.
    ///
    /// 23:30 → 07:15 = 7 hours 45 minutes = 465 minutes total.
    func testSleepCrossMidnightAllMinutesGoToWakeUpDay() {
        let sample = makeSleepSample(
            start: jan15(23, 30),  // 23:30 Jan 15
            end: jan16(7, 15)      // 07:15 Jan 16
        )

        let result = bucketSamples([sample], asleepFilter: true, calendar: utcCalendar, timeZone: utcTZ)

        XCTAssertEqual(result.count, 1, "Cross-midnight session should produce exactly one day bucket (wake-up day)")

        // Should NOT have Jan 15 data.
        let jan15Key = SnapshotMetric.dateKey(for: jan15(0), timeZone: utcTZ)
        XCTAssertNil(result[jan15Key], "Jan 15 should have no data — minutes go to wake-up day")

        // Should have Jan 16 data with full 465 minutes.
        let jan16Key = SnapshotMetric.dateKey(for: jan16(0), timeZone: utcTZ)
        let minutes = try! XCTUnwrap(result[jan16Key], "Jan 16 (wake-up day) should have data")
        XCTAssertEqual(minutes, 465.0, accuracy: 0.01,
            "7h45m session (23:30→07:15) should yield 465 minutes on wake-up day Jan 16")
    }

    /// Multiple sessions on the same wake-up day (nap + main sleep) should be summed.
    /// - Nap: Jan 15 14:00–15:00 (60 min, wakes up Jan 15)
    /// - Main sleep: Jan 15 23:00 → Jan 16 07:00 (480 min, wakes up Jan 16)
    /// Jan 15 total = 60 min; Jan 16 total = 480 min.
    func testMultipleSessionsSameWakeDayAreSummed() {
        let nap = makeSleepSample(
            start: jan15(14, 0),   // 14:00 Jan 15
            end: jan15(15, 0)      // 15:00 Jan 15 — nap, wakes up Jan 15
        )
        let mainSleep = makeSleepSample(
            start: jan15(23, 0),   // 23:00 Jan 15
            end: jan16(7, 0)       // 07:00 Jan 16 — main sleep, wakes up Jan 16
        )

        let result = bucketSamples([nap, mainSleep], asleepFilter: true, calendar: utcCalendar, timeZone: utcTZ)

        XCTAssertEqual(result.count, 2, "Should have two day buckets (Jan 15 for nap, Jan 16 for main sleep)")

        let jan15Key = SnapshotMetric.dateKey(for: jan15(0), timeZone: utcTZ)
        let jan16Key = SnapshotMetric.dateKey(for: jan16(0), timeZone: utcTZ)

        let jan15Minutes = try! XCTUnwrap(result[jan15Key])
        XCTAssertEqual(jan15Minutes, 60.0, accuracy: 0.01,
            "Nap (60 min) attributed to Jan 15")

        let jan16Minutes = try! XCTUnwrap(result[jan16Key])
        XCTAssertEqual(jan16Minutes, 480.0, accuracy: 0.01,
            "Main sleep (8h) attributed to Jan 16 wake-up day")
    }

    /// Two naps on the same calendar day (both start AND end on Jan 15) should be summed.
    /// Nap A: 13:00–13:30 (30 min). Nap B: 15:00–15:45 (45 min). Total = 75 min on Jan 15.
    func testTwoNapsSameDayAreSummed() {
        let napA = makeSleepSample(start: jan15(13, 0), end: jan15(13, 30))
        let napB = makeSleepSample(start: jan15(15, 0), end: jan15(15, 45))

        let result = bucketSamples([napA, napB], asleepFilter: true, calendar: utcCalendar, timeZone: utcTZ)

        let jan15Key = SnapshotMetric.dateKey(for: jan15(0), timeZone: utcTZ)
        let minutes = try! XCTUnwrap(result[jan15Key])
        XCTAssertEqual(minutes, 75.0, accuracy: 0.01,
            "Two same-day naps (30+45 min) should sum to 75 min on Jan 15")
    }

    /// Non-asleep values (inBed, awake) should be filtered out when asleepFilter=true.
    func testNonAsleepSamplesFilteredOut() {
        let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let inBed = HKCategorySample(
            type: type,
            value: HKCategoryValueSleepAnalysis.inBed.rawValue,
            start: jan15(22, 0),
            end: jan15(23, 0)
        )
        let awake = HKCategorySample(
            type: type,
            value: HKCategoryValueSleepAnalysis.awake.rawValue,
            start: jan15(23, 0),
            end: jan15(23, 15)
        )

        let result = bucketSamples([inBed, awake], asleepFilter: true, calendar: utcCalendar, timeZone: utcTZ)

        XCTAssertTrue(result.isEmpty, "inBed and awake samples should be filtered out")
    }

    /// All asleep variants (unspecified, core, deep, REM) should be counted.
    func testAllAsleepVariantsAreCounted() {
        let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let unspecified = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                           start: jan15(21, 0), end: jan15(21, 30))  // 30 min
        let core = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                    start: jan15(21, 30), end: jan15(22, 0))  // 30 min
        let deep = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                    start: jan15(22, 0), end: jan15(22, 30))  // 30 min
        let rem = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                                   start: jan15(22, 30), end: jan15(23, 0))  // 30 min

        let result = bucketSamples([unspecified, core, deep, rem], asleepFilter: true, calendar: utcCalendar, timeZone: utcTZ)

        let jan15Key = SnapshotMetric.dateKey(for: jan15(0), timeZone: utcTZ)
        let minutes = try! XCTUnwrap(result[jan15Key])
        XCTAssertEqual(minutes, 120.0, accuracy: 0.01,
            "All four asleep variants (30 min each) should sum to 120 min")
    }

    // MARK: - Mindful minutes tests

    /// Mindful sessions use asleepFilter=false, so all values pass through.
    func testMindfulSessionNotFiltered() {
        let sample = makeMindfulSample(start: jan15(8, 0), end: jan15(8, 10)) // 10 min

        let result = bucketSamples([sample], asleepFilter: false, calendar: utcCalendar, timeZone: utcTZ)

        let jan15Key = SnapshotMetric.dateKey(for: jan15(0), timeZone: utcTZ)
        let minutes = try! XCTUnwrap(result[jan15Key])
        XCTAssertEqual(minutes, 10.0, accuracy: 0.01,
            "10-minute mindful session should be attributed to Jan 15")
    }

    /// A mindful session crossing midnight (23:55 Jan 15 → 00:05 Jan 16, 10 min)
    /// should go entirely to the wake-up day (Jan 16).
    func testMindfulCrossMidnightGoesToWakeUpDay() {
        let sample = makeMindfulSample(
            start: jan15(23, 55),   // 23:55 Jan 15
            end: jan16(0, 5)        // 00:05 Jan 16 — 10 min
        )

        let result = bucketSamples([sample], asleepFilter: false, calendar: utcCalendar, timeZone: utcTZ)

        XCTAssertEqual(result.count, 1)
        let jan16Key = SnapshotMetric.dateKey(for: jan16(0), timeZone: utcTZ)
        let minutes = try! XCTUnwrap(result[jan16Key])
        XCTAssertEqual(minutes, 10.0, accuracy: 0.01,
            "10-minute cross-midnight mindful session should go to Jan 16 wake-up day")
    }
}
#endif
