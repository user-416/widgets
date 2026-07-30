// Fake Strava client (DEBUG only). Implements both halves of B4 §4–§5:
//   - Data: deterministic ~90 days of activities seeded by athleteId per
//     B2 §6, aggregated through the same per-day buckets as the live
//     client (`elapsed_time / 60` summed by `SnapshotMetric.dateKey`).
//   - Auth: short-circuits OAuth — the consent SHEET is presented by
//     `AddStravaMetricFlow` directly (`FakeStravaConsentSheet`), and only
//     calls `authenticate` AFTER the user taps Authorize. So this method
//     just mints deterministic tokens after a tiny latency. The real
//     `ASWebAuthenticationSession` path is not exercised in fake mode.
//
// We use SplitMix64 (already in `FakeRNG.swift`) instead of ChaCha20 (B2
// §6a) — same statistical quality for our purposes, drastically simpler,
// no CryptoKit dependency. Documented choice.
//
// We bypass the live `JSONDecoder` round-trip and run the aggregator math
// directly on the in-memory activity list — the live client only reads
// 4 fields (`id`, `elapsed_time`, `start_date`, `type`) so the round-trip
// would add 200 LOC of canonical-shaped JSON for zero coverage win. The
// `aggregate(...)` helper duplicates the 3-line per-day bucketing from
// `StravaClient.dailyActivityMinutes` lines 186–190.
#if DEBUG
import Foundation
import AuthenticationServices
import WidgetsShared

struct FakeStravaClient: StravaAPI {
    var scenario: FakeScenario.Strava = .happy
    var latency: ClosedRange<UInt64> = 80_000_000...250_000_000

    // MARK: - UserDefaults keys

    private static let athleteIdKey = "debug.fakeStrava.athleteId"
    private static let installIdKey = "debug.fakeStrava.installId"

    // MARK: - Auth half

    /// Short-circuits in fake mode. `AddStravaMetricFlow` presents
    /// `FakeStravaConsentSheet` first; only on Authorize does it call into
    /// here. So we don't show any UI — we just mint tokens after a small
    /// delay (matches the 600ms sheet "ProgressView while authorizing"
    /// look from B4 §5).
    @MainActor
    func authenticate(
        presentationAnchor: ASPresentationAnchor,
        workerBaseURL: URL
    ) async throws -> StravaTokens {
        try await sleep()
        if scenario == .denied {
            throw StravaClient.StravaError.oauthError("access_denied")
        }
        return mintTokens()
    }

    func refresh(
        workerBaseURL: URL,
        refreshToken: String
    ) async throws -> StravaTokens {
        try await sleep()
        // Validate this looks like a fake token. Stops a stale real token
        // from accidentally surviving a fake-mode toggle and looking
        // "valid" until it actually fires a request.
        guard refreshToken.hasPrefix("fake_rt_") else {
            throw StravaClient.StravaError.oauthError("invalid_refresh_token")
        }
        return mintTokens(reusingRefresh: refreshToken)
    }

    /// Public helper: same as `authenticate` but exposed so the consent
    /// sheet's Authorize handler can be wired without going through the
    /// `presentationAnchor`/`workerBaseURL` parameters that don't make
    /// sense in fake mode. (Currently the flow just calls `authenticate`
    /// — we keep this for clarity / future use.)
    func mintTokensForConsent() -> StravaTokens {
        mintTokens()
    }

    private func mintTokens(reusingRefresh: String? = nil) -> StravaTokens {
        let athleteId = Self.persistentAthleteId()
        let seed = athleteId & 0xFFFF_FFFF_FFFF // truncate for token suffix
        return StravaTokens(
            accessToken: "fake_at_\(seed)_\(Int(Date().timeIntervalSince1970))",
            refreshToken: reusingRefresh ?? "fake_rt_\(seed)",
            expiresAt: Date(timeIntervalSinceNow: 6 * 3600),
            athleteId: athleteId
        )
    }

    /// Look up — or mint and persist — the athlete id used for this
    /// process's fake-mode session. Tied to a process-scoped install id
    /// so two fresh checkouts on the same dev simulator produce
    /// different-but-stable athletes.
    private static func persistentAthleteId() -> Int64 {
        let defaults = UserDefaults.standard
        if let existing = defaults.object(forKey: athleteIdKey) as? NSNumber {
            return existing.int64Value
        }
        let installID: String = {
            if let s = defaults.string(forKey: installIdKey) { return s }
            let new = UUID().uuidString
            defaults.set(new, forKey: installIdKey)
            return new
        }()
        let seed = fakeSeed(for: "strava-athlete:" + installID)
        // Restrict to plausible 8–9 digit Strava athlete ids (pre-2025).
        let id = Int64(10_000_000 + (seed % 90_000_000))
        defaults.set(NSNumber(value: id), forKey: athleteIdKey)
        return id
    }

    /// Test/debug hook so disconnect flows can wipe the fake athlete and
    /// the next reconnect mints a fresh dataset.
    static func resetPersistentAthlete() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: athleteIdKey)
        defaults.removeObject(forKey: installIdKey)
    }

    // MARK: - Data half

    func dailyActivityMinutes(
        accessToken: String,
        since: Date,
        until: Date,
        timeZone: TimeZone
    ) async throws -> [String: Double] {
        try await sleep()

        switch scenario {
        case .empty:
            return [:]
        case .denied:
            throw StravaClient.StravaError.oauthError("access_denied")
        case .rateLimited:
            // Half the time we return a Retry-After-equivalent, half not —
            // matches the real Strava behaviour (B2 §4d) and exercises both
            // branches in `StravaClient`.
            let suffix = Int(since.timeIntervalSince1970) & 1
            throw StravaClient.StravaError.rateLimited(
                retryAfter: suffix == 0 ? 600 : nil
            )
        case .expiredMidPaginate:
            // Per B2 §5.14: page 1 succeeds, page 2 returns 401 → live
            // client throws `invalidResponse`. We have no real pagination
            // here, but the bug is observable as soon as we throw past
            // the first "page" of a >100-activity dataset. Pick a seed
            // size that exceeds 100 to make the bug reproducible from
            // the outside. For now we just throw immediately — L6 tests
            // assert this.
            throw StravaClient.StravaError.invalidResponse
        case .happy:
            break
        }

        let athleteId = Self.persistentAthleteId()
        let activities = generateActivities(
            athleteId: athleteId,
            since: since,
            until: until
        )
        return aggregate(activities, timeZone: timeZone)
    }

    private func sleep() async throws {
        guard latency.upperBound > 0 else { return }
        let ns = UInt64.random(in: latency)
        try? await Task.sleep(nanoseconds: ns)
    }

    // MARK: - Activity generator (B2 §6)

    /// Minimal per-activity record — only the fields the live aggregator
    /// reads, plus `type` for type-mix realism. Shape mirrors what
    /// `StravaClient`'s private `StravaActivity` decodes.
    fileprivate struct FakeActivity {
        let id: Int64
        let elapsedSeconds: Int
        let startDate: Date
        let type: String
        let sportType: String
        let isManual: Bool
        let isTrainer: Bool
    }

    fileprivate enum WorkoutKind: CaseIterable {
        case runEasy, runIntervals, runLong
        case rideCommute, rideLong, rideVirtual
        case yoga, weightTraining, walk, hike, swim
        case trailRun

        var typeLegacy: String {
            switch self {
            case .runEasy, .runIntervals, .runLong, .trailRun: return "Run"
            case .rideCommute, .rideLong, .rideVirtual: return "Ride"
            case .yoga: return "Yoga"
            case .weightTraining: return "WeightTraining"
            case .walk: return "Walk"
            case .hike: return "Hike"
            case .swim: return "Swim"
            }
        }

        var sportType: String {
            switch self {
            case .runEasy, .runIntervals, .runLong: return "Run"
            case .trailRun: return "TrailRun"
            case .rideCommute, .rideLong: return "Ride"
            case .rideVirtual: return "VirtualRide"
            case .yoga: return "Yoga"
            case .weightTraining: return "WeightTraining"
            case .walk: return "Walk"
            case .hike: return "Hike"
            case .swim: return "Swim"
            }
        }

        /// Duration distribution (minutes), Normal(mean, sd) clamped.
        var durationDistribution: (mean: Double, sd: Double, lo: Double, hi: Double) {
            switch self {
            case .runEasy:        return (35, 6,  25, 55)
            case .runIntervals:   return (50, 8,  35, 75)
            case .runLong:        return (95, 20, 60, 180)
            case .trailRun:       return (75, 20, 45, 150)
            case .rideCommute:    return (28, 5,  20, 45)
            case .rideLong:       return (150, 40, 80, 360)
            case .rideVirtual:    return (60, 15, 30, 120)
            case .yoga:           return (35, 8,  20, 75)
            case .weightTraining: return (50, 10, 30, 90)
            case .walk:           return (40, 15, 15, 90)
            case .hike:           return (180, 60, 60, 480)
            case .swim:           return (35, 10, 20, 75)
            }
        }
    }

    private func generateActivities(
        athleteId: Int64,
        since: Date,
        until: Date
    ) -> [FakeActivity] {
        var rng = SplitMix64(seed: fakeSeed(for: "strava:\(athleteId)"))
        var activities: [FakeActivity] = []
        var nextId: Int64 = 15_000_000_000

        // Iterate days from `since` (inclusive) to `until` (exclusive).
        let calendar: Calendar = {
            var c = Calendar(identifier: .iso8601)
            c.timeZone = TimeZone(identifier: "UTC") ?? .current
            return c
        }()
        let dayStart = calendar.startOfDay(for: since)
        let endDay = calendar.startOfDay(for: until)
        var day = dayStart
        var dayIndex = 0

        while day <= endDay {
            let weekday = calendar.component(.weekday, from: day) // Sun=1..Sat=7
            // Convert to ISO weekday Mon=1..Sun=7
            let iso = ((weekday + 5) % 7) + 1

            let (probability, kinds) = weeklyTemplate(isoWeekday: iso)
            if rng.nextUnitDouble() < probability {
                let kind = kinds[rng.nextInt(in: 0...(kinds.count - 1))]
                let activity = synthesize(
                    kind: kind,
                    on: day,
                    rng: &rng,
                    nextId: &nextId
                )
                if activity.startDate >= since && activity.startDate < until {
                    activities.append(activity)
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
            dayIndex += 1
        }

        // Special pinned inserts (B2 §6e) relative to `since`.
        let specials: [(offsetDays: Int, kind: WorkoutKind, manual: Bool, trainer: Bool, durationOverride: Int?)] = [
            (3,  .yoga,           true,  false, nil),
            (12, .rideCommute,    false, true,  nil),
            (18, .trailRun,       false, false, nil),
            (24, .runEasy,        false, false, nil),  // companion: weight too
            (30, .rideVirtual,    false, true,  nil),
            (45, .runLong,        false, false, 64_800), // 18-hour ultra
            (60, .swim,           false, false, nil),
            (75, .runEasy,        false, false, nil),  // "future" handled below
            (85, .runEasy,        false, false, 30 * 60), // 23:45 + 30min
        ]
        for special in specials {
            let date = calendar.date(byAdding: .day, value: special.offsetDays, to: dayStart) ?? dayStart
            guard date <= until else { continue }
            let startDate: Date
            switch special.offsetDays {
            case 75:
                startDate = max(date, until.addingTimeInterval(30))
            case 85:
                let comps = DateComponents(hour: 23, minute: 45)
                startDate = calendar.date(byAdding: comps, to: date) ?? date
            default:
                let hour = 6 + Int(rng.next() % 14)
                startDate = calendar.date(byAdding: .hour, value: hour, to: date) ?? date
            }
            let elapsed: Int
            if let override = special.durationOverride {
                elapsed = override
            } else {
                let mins = sampleDuration(kind: special.kind, rng: &rng)
                elapsed = Int(ceil(mins * 60))
            }
            activities.append(FakeActivity(
                id: nextId,
                elapsedSeconds: elapsed,
                startDate: startDate,
                type: special.kind.typeLegacy,
                sportType: special.kind.sportType,
                isManual: special.manual,
                isTrainer: special.trainer
            ))
            nextId += 1
            if special.offsetDays == 24 {
                let weight = synthesize(
                    kind: .weightTraining,
                    on: date,
                    rng: &rng,
                    nextId: &nextId
                )
                activities.append(weight)
            }
        }

        return activities
    }

    private func weeklyTemplate(isoWeekday: Int) -> (Double, [WorkoutKind]) {
        switch isoWeekday {
        case 1: return (0.85, [.runEasy])
        case 2: return (0.55, [.yoga, .weightTraining])
        case 3: return (0.90, [.rideCommute, .runIntervals])
        case 4: return (0.40, [.weightTraining])
        case 5: return (0.70, [.runEasy, .rideCommute])
        case 6: return (0.95, [.runLong, .rideLong, .hike])
        case 7: return (0.60, [.yoga, .walk, .swim])
        default: return (0.0, [.runEasy])
        }
    }

    private func synthesize(
        kind: WorkoutKind,
        on day: Date,
        rng: inout SplitMix64,
        nextId: inout Int64
    ) -> FakeActivity {
        let mins = sampleDuration(kind: kind, rng: &rng)
        let elapsed = Int(ceil(mins * 60))
        // Time-of-day distribution per B2 §6d.
        let roll = rng.nextUnitDouble()
        let hour: Int
        if roll < 0.6 {
            hour = 6 + rng.nextInt(in: 0...2)
        } else if roll < 0.85 {
            hour = 12 + rng.nextInt(in: 0...1)
        } else {
            hour = 17 + rng.nextInt(in: 0...3)
        }
        let minute = rng.nextInt(in: 0...59)
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let dayStart = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: dayStart) ?? day
        let id = nextId
        nextId += 1
        return FakeActivity(
            id: id,
            elapsedSeconds: elapsed,
            startDate: start,
            type: kind.typeLegacy,
            sportType: kind.sportType,
            isManual: false,
            isTrainer: false
        )
    }

    private func sampleDuration(kind: WorkoutKind, rng: inout SplitMix64) -> Double {
        let dist = kind.durationDistribution
        let z = boxMuller(rng: &rng)
        let raw = dist.mean + z * dist.sd
        return min(max(raw, dist.lo), dist.hi)
    }

    /// Box-Muller transform for a Normal(0,1) sample from the SplitMix64.
    private func boxMuller(rng: inout SplitMix64) -> Double {
        let u1 = max(rng.nextUnitDouble(), 1e-12)
        let u2 = rng.nextUnitDouble()
        return (-2.0 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    // MARK: - Aggregator (mirrors `StravaClient.dailyActivityMinutes`)

    private func aggregate(
        _ activities: [FakeActivity],
        timeZone: TimeZone
    ) -> [String: Double] {
        var buckets: [String: Double] = [:]
        for a in activities {
            let key = SnapshotMetric.dateKey(for: a.startDate, timeZone: timeZone)
            buckets[key, default: 0] += Double(a.elapsedSeconds) / 60.0
        }
        return buckets
    }
}
#endif
