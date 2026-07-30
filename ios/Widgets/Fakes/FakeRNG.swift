// Deterministic seeded PRNG and shared FakeScenario knobs used by the
// fake integration clients. All DEBUG-only — fake mode is compiled out
// in RELEASE builds so this file ships zero bytes to the App Store.
//
// Implementation per B4 §4b. SplitMix64 is small, fast, and produces
// well-distributed 64-bit outputs from a single 64-bit seed — perfect
// for hashing a key string into a reproducible per-account heatmap.
#if DEBUG
import Foundation

/// SplitMix64 PRNG. Conforms to `RandomNumberGenerator` so it slots into
/// `Int.random(in:using:)`, `Double.random(in:using:)`, etc.
///
/// Reference: https://prng.di.unimi.it/splitmix64.c (public domain).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the 0-state degenerate case by adding the canonical
        // golden-ratio constant; SplitMix64 itself is well-defined for
        // every seed but starting at 0 yields a predictable first byte.
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Convenience: uniform Double in [0, 1).
    mutating func nextUnitDouble() -> Double {
        // Use top 53 bits — the precision of a Double mantissa.
        let bits = next() >> 11
        return Double(bits) / Double(1 << 53)
    }

    /// Convenience: uniform Double in `range`.
    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * nextUnitDouble()
    }

    /// Convenience: uniform Int in `range` (inclusive).
    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }
}

/// Stable 64-bit hash of a string, used to derive a SplitMix64 seed.
/// We avoid `String.hashValue` because it's salted per-process — same
/// key would yield different fake data on every cold start. This FNV-1a
/// 64-bit variant is deterministic across runs and architectures.
func fakeSeed(for string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a 64 offset basis
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01B3 // FNV-1a 64 prime
    }
    return hash
}

/// Scenario knobs for fault injection. Settings → Debug exposes a
/// picker per integration; tests construct fakes with explicit cases.
struct FakeScenario: Sendable {
    enum Strava: Sendable { case happy, rateLimited, expiredMidPaginate, denied, empty }
    enum Health: Sendable { case happy, denied, empty }

    var strava: Strava = .happy
    var health: Health = .happy
    /// Per-call latency window in nanoseconds. Tests pass `0...0`.
    var latency: ClosedRange<UInt64> = 80_000_000...250_000_000
}
#endif
