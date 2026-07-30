import Foundation

public enum Thresholds {
    /// Maps a daily count to a bucket index 0...4 based on four cutoffs.
    ///
    /// `thresholds` must contain exactly 4 values: [c0, c1, c2, c3].
    /// - count <= 0          → 0
    /// - 0 < count < c1      → 1
    /// - c1 <= count < c2    → 2
    /// - c2 <= count < c3    → 3
    /// - count >= c3         → 4
    ///
    /// `c0` is informational (the minimum count that registers as 1) and is currently
    /// equivalent to "count > 0", but kept in the array for symmetry and future use.
    public static func bucket(for count: Double, thresholds: [Double]) -> Int {
        guard count > 0 else { return 0 }
        guard thresholds.count >= 4 else { return 1 }
        if count >= thresholds[3] { return 4 }
        if count >= thresholds[2] { return 3 }
        if count >= thresholds[1] { return 2 }
        return 1
    }
}
