// Deterministic fake HealthKit client. Produces stable step/workout
// dictionaries so screenshots and dev runs see the same heatmap shape
// every time. Per B4 §4b, Health uses a constant seed (42) — there's
// no per-account key to vary on. We further branch the step and
// workout streams onto disjoint splitmix64 seeds derived from
// "health:steps" and "health:workouts" so the two methods never
// coincidentally produce the same heatmap.
//
// The recipe mirrors `Services/SampleData.swift` (180-day window with
// weekly seasonality and a recent boost) so toggling fake mode in dev
// shows visuals consistent with the "Seed sample data" debug action.
// Steps/workouts have wildly different magnitudes (counts vs minutes)
// and recipes specifically tuned to look distinct from the Strava
// fakes when both are lit up side-by-side.
//
// New metrics (sleep, active energy, mindful minutes, HRV, resting HR,
// body mass) use simple deterministic generators with plausible ranges.
#if DEBUG
import Foundation
import WidgetsShared

struct FakeHealthClient: HealthDataReading {
    var scenario: FakeScenario.Health = .happy

    func requestAuthorization() async throws -> Bool {
        switch scenario {
        case .happy:
            // Simulate the small system-prompt delay so callers exercise
            // their loading UI in fake mode the same way they do in live.
            try? await Task.sleep(nanoseconds: 200_000_000)
            return true
        case .denied:
            return false
        case .empty:
            // Auth granted, but every query will return [:] below.
            return true
        }
    }

    func dailySteps(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        switch scenario {
        case .empty:
            return [:]
        case .denied:
            throw HealthKitError.authorizationDenied
        case .happy:
            return Self.generate(
                daysBack: daysBack,
                endDate: endDate,
                timeZone: timeZone,
                seed: fakeSeed(for: "health:steps"),
                kind: .steps
            )
        }
    }

    func dailyWorkoutMinutes(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        switch scenario {
        case .empty:
            return [:]
        case .denied:
            throw HealthKitError.authorizationDenied
        case .happy:
            return Self.generate(
                daysBack: daysBack,
                endDate: endDate,
                timeZone: timeZone,
                seed: fakeSeed(for: "health:workouts"),
                kind: .workouts
            )
        }
    }

    func dailySleep(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        switch scenario {
        case .empty: return [:]
        case .denied: throw HealthKitError.authorizationDenied
        case .happy:
            return Self.generateSimple(
                daysBack: daysBack,
                endDate: endDate,
                timeZone: timeZone,
                seed: fakeSeed(for: "health:sleep"),
                minValue: 300,   // 5h in minutes
                maxValue: 540    // 9h in minutes
            )
        }
    }

    func dailyActiveEnergy(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        switch scenario {
        case .empty: return [:]
        case .denied: throw HealthKitError.authorizationDenied
        case .happy:
            return Self.generateSimple(
                daysBack: daysBack,
                endDate: endDate,
                timeZone: timeZone,
                seed: fakeSeed(for: "health:active_energy"),
                minValue: 150,   // kcal
                maxValue: 700
            )
        }
    }

    func dailyMindfulMinutes(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        switch scenario {
        case .empty: return [:]
        case .denied: throw HealthKitError.authorizationDenied
        case .happy:
            // Mindfulness is sparse — only ~40% of days have data.
            return Self.generateSparse(
                daysBack: daysBack,
                endDate: endDate,
                timeZone: timeZone,
                seed: fakeSeed(for: "health:mindful"),
                probability: 0.4,
                minValue: 5,
                maxValue: 30
            )
        }
    }

    func dailyHRV(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        switch scenario {
        case .empty: return [:]
        case .denied: throw HealthKitError.authorizationDenied
        case .happy:
            return Self.generateSimple(
                daysBack: daysBack,
                endDate: endDate,
                timeZone: timeZone,
                seed: fakeSeed(for: "health:hrv"),
                minValue: 20,   // ms
                maxValue: 80
            )
        }
    }

    func dailyRestingHR(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        switch scenario {
        case .empty: return [:]
        case .denied: throw HealthKitError.authorizationDenied
        case .happy:
            return Self.generateSimple(
                daysBack: daysBack,
                endDate: endDate,
                timeZone: timeZone,
                seed: fakeSeed(for: "health:resting_hr"),
                minValue: 50,   // bpm
                maxValue: 75
            )
        }
    }

    func dailyBodyMass(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        switch scenario {
        case .empty: return [:]
        case .denied: throw HealthKitError.authorizationDenied
        case .happy:
            // Body mass changes slowly — tight band around 75kg with small drift.
            return Self.generateSimple(
                daysBack: daysBack,
                endDate: endDate,
                timeZone: timeZone,
                seed: fakeSeed(for: "health:body_mass"),
                minValue: 72.0,
                maxValue: 78.0
            )
        }
    }

    // MARK: - Recipe

    private enum Kind {
        case steps      // counts; weekday-leaning, momentum near today
        case workouts   // minutes; weekend-leaning, sparse weekdays
    }

    /// Deterministic 180-day generator. Seasonality + bias are fixed by
    /// `kind`; per-day jitter is drawn from a splitmix64 stream seeded
    /// stably so the same `(seed, kind, endDate-day)` always yields the
    /// same value. Only the most recent `daysBack` days are returned.
    private static func generate(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone,
        seed: UInt64,
        kind: Kind
    ) -> [String: Double] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: endDate)

        // Per-call SplitMix64. Disjoint seed per kind keeps the two
        // heatmaps visually distinct even though they share a recipe.
        var rng = SplitMix64(seed: seed)
        // Reserve a fixed-length jitter table so the values are stable
        // regardless of `daysBack`: index 0 = today, 1 = yesterday, etc.
        let window = 180
        var jitter: [Double] = []
        jitter.reserveCapacity(window)
        for _ in 0..<window {
            jitter.append(rng.nextUnitDouble())
        }

        var bucket: [String: Double] = [:]
        let span = min(window, max(0, daysBack))
        for offset in 0..<span {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: date)
            let isWeekend = (weekday == 1 || weekday == 7)
            let value = recipe(
                kind: kind,
                offset: offset,
                isWeekend: isWeekend,
                jitter: jitter[offset]
            )
            guard value > 0 else { continue }
            let key = SnapshotMetric.dateKey(for: date, timeZone: timeZone)
            bucket[key] = value
        }
        return bucket
    }

    /// Simple continuous generator for metrics with daily presence (sleep, HRV, etc.).
    private static func generateSimple(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone,
        seed: UInt64,
        minValue: Double,
        maxValue: Double
    ) -> [String: Double] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: endDate)

        var rng = SplitMix64(seed: seed)
        let window = min(180, daysBack)
        var bucket: [String: Double] = [:]
        for offset in 0..<window {
            let jitter = rng.nextUnitDouble()
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let value = minValue + (maxValue - minValue) * jitter
            let key = SnapshotMetric.dateKey(for: date, timeZone: timeZone)
            bucket[key] = value
        }
        return bucket
    }

    /// Sparse generator for metrics that don't occur every day (mindful sessions, etc.).
    private static func generateSparse(
        daysBack: Int,
        endDate: Date,
        timeZone: TimeZone,
        seed: UInt64,
        probability: Double,
        minValue: Double,
        maxValue: Double
    ) -> [String: Double] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: endDate)

        var rng = SplitMix64(seed: seed)
        let window = min(180, daysBack)
        var bucket: [String: Double] = [:]
        for offset in 0..<window {
            let roll = rng.nextUnitDouble()
            let jitter = rng.nextUnitDouble()
            guard roll < probability else { continue }
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let value = minValue + (maxValue - minValue) * jitter
            let key = SnapshotMetric.dateKey(for: date, timeZone: timeZone)
            bucket[key] = value
        }
        return bucket
    }

    private static func recipe(
        kind: Kind,
        offset: Int,
        isWeekend: Bool,
        jitter: Double
    ) -> Double {
        let day = Double(offset)
        let week = day / 7.0

        switch kind {
        case .steps:
            // Realistic step counts: ~5k–14k weekdays, lighter on
            // weekends, with a slow seasonal swell and last-2-week
            // momentum boost mirroring SampleData's recentBoost.
            let base = 8500.0
                + 2200.0 * sin(week * 0.42)
                + 1100.0 * cos(day * 0.21)
            let dayMultiplier = isWeekend ? 0.78 : 1.12
            let recent = offset < 14 ? 1.18 : 1.0
            // ±12% jitter, deterministic per-day.
            let jitterMul = 0.88 + 0.24 * jitter
            let raw = base * dayMultiplier * recent * jitterMul
            return max(0, raw.rounded())

        case .workouts:
            // Workout minutes: weekend-leaning, mostly 0–60 min, with
            // honest gaps. Weekday probability is low so the heatmap
            // shows scattered weekend dots — visibly different from
            // the dense steps grid.
            let probability: Double = isWeekend ? 0.78 : 0.34
            // Use a separate slice of the jitter draw to decide
            // presence vs. magnitude so the two are uncorrelated.
            let presence = jitter
            guard presence < probability else { return 0 }
            let envelope = 0.55 + 0.35 * sin(week * 0.6)
            // Magnitude in [15, 75] minutes, weekend-skewed up.
            let magnitudeJitter = (presence / probability) // [0, 1)
            let weekendBonus = isWeekend ? 12.0 : 0.0
            let raw = (15.0 + 60.0 * magnitudeJitter * envelope) + weekendBonus
            return max(0, raw.rounded())
        }
    }
}
#endif
