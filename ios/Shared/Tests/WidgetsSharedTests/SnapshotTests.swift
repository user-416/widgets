import Foundation
import Testing
@testable import WidgetsShared

struct SnapshotTests {
    @Test func dateKeyIsStableAndZeroPadded() {
        var comp = DateComponents()
        comp.year = 2026
        comp.month = 4
        comp.day = 7
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let date = cal.date(from: comp)!
        #expect(SnapshotMetric.dateKey(for: date, timeZone: cal.timeZone) == "2026-04-07")
    }

    @Test func roundTripCodable() throws {
        let metric = SnapshotMetric(
            id: "abc",
            name: "Sales calls",
            kind: .manual,
            color: .githubGreen,
            thresholds: [1, 2, 4, 7],
            days: ["2026-04-26": 3, "2026-04-25": 1]
        )
        let snapshot = Snapshot(generatedAt: Date(), metrics: [metric])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(Snapshot.self, from: data)
        #expect(decoded.metrics.count == 1)
        #expect(decoded.metrics[0].days["2026-04-26"] == 3)
    }

    @Test func countOnDateLooksUpByKey() {
        let metric = SnapshotMetric(
            id: "abc",
            name: "x",
            kind: .manual,
            color: .githubGreen,
            thresholds: [1, 2, 4, 7],
            days: ["2026-04-26": 5]
        )
        var comp = DateComponents()
        comp.year = 2026; comp.month = 4; comp.day = 26
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let d = cal.date(from: comp)!
        #expect(metric.count(on: d) == 5)
    }
}
