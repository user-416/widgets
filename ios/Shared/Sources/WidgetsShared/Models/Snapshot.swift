import Foundation

public struct Snapshot: Codable, Sendable {
    public var generatedAt: Date
    public var metrics: [SnapshotMetric]

    public init(generatedAt: Date, metrics: [SnapshotMetric]) {
        self.generatedAt = generatedAt
        self.metrics = metrics
    }

    public static let empty = Snapshot(generatedAt: .distantPast, metrics: [])
}

public struct SnapshotMetric: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var kind: MetricKind
    public var color: PaletteName
    /// Four cutoff values mapping a count to one of five buckets (0..4):
    /// bucket 0 if count <= 0
    /// bucket 1 if count > 0 and count < thresholds[1]
    /// bucket 2 if count >= thresholds[1] and count < thresholds[2]
    /// bucket 3 if count >= thresholds[2] and count < thresholds[3]
    /// bucket 4 if count >= thresholds[3]
    /// (thresholds[0] is conventionally the minimum count for bucket 1, used in defaults)
    public var thresholds: [Double]
    /// "yyyy-MM-dd" (Gregorian, user timezone) → count
    public var days: [String: Double]

    public init(id: String, name: String, kind: MetricKind, color: PaletteName, thresholds: [Double], days: [String: Double]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.color = color
        self.thresholds = thresholds
        self.days = days
    }
}

public extension SnapshotMetric {
    /// Stable yyyy-MM-dd in the supplied (or current) timezone, Gregorian calendar.
    static func dateKey(for date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comp = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comp.year ?? 0, comp.month ?? 0, comp.day ?? 0)
    }

    func count(on date: Date, timeZone: TimeZone = .current) -> Double {
        days[Self.dateKey(for: date, timeZone: timeZone)] ?? 0
    }

    /// Total over the trailing 365 days ending at `endDate`.
    func totalLastYear(endingAt endDate: Date = Date(), timeZone: TimeZone = .current) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var total: Double = 0
        for offset in 0..<365 {
            guard let d = cal.date(byAdding: .day, value: -offset, to: endDate) else { continue }
            total += count(on: d, timeZone: timeZone)
        }
        return total
    }
}
