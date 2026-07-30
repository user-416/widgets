#if DEBUG
import Foundation
import SwiftData
import WidgetsShared

enum SampleData {
    /// Deterministic sample-data generator. The shape of each metric is hand-tuned
    /// to look like a real, motivated user's year — peaks on weekdays/weekends as
    /// appropriate, momentum near "today", honest gaps. No RNG: same seed every
    /// time so screenshots are stable.
    @MainActor
    static func seed(into context: ModelContext) {
        struct Preset {
            let name: String
            let color: PaletteName
            // (offset_from_today_in_days) -> count
            let curve: (Int) -> Double
            let weekdayBias: Double  // multiplier for weekday counts
            let weekendBias: Double  // multiplier for weekend counts
            let recentBoost: Double  // last 14 days get this multiplier
            let cap: Double
        }

        let presets: [Preset] = [
            Preset(
                name: "Sales calls",
                color: .githubGreen,
                curve: { offset in
                    // Slow ramp: weeks of build-up, dip mid-quarter, surge recently
                    let week = Double(offset) / 7.0
                    let base = 3.5 - 1.2 * cos(week * 0.42) - 0.8 * sin(week * 0.18)
                    return max(0, base)
                },
                weekdayBias: 1.4, weekendBias: 0.15,
                recentBoost: 1.5, cap: 8
            ),
            Preset(
                name: "Deep focus",
                color: .blue,
                curve: { offset in
                    // Two work sessions on most weekdays, varied
                    let day = Double(offset)
                    return 2.4 + 1.6 * sin(day * 0.31) + 0.9 * cos(day * 0.11)
                },
                weekdayBias: 1.3, weekendBias: 0.5,
                recentBoost: 1.2, cap: 6
            ),
            Preset(
                name: "Workouts",
                color: .orange,
                curve: { offset in
                    // Lighter, mostly weekends, sparse weekdays
                    let week = Double(offset) / 7.0
                    return 0.8 + 0.6 * sin(week * 0.6)
                },
                weekdayBias: 0.4, weekendBias: 1.6,
                recentBoost: 1.3, cap: 3
            ),
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = Date()

        for (idx, preset) in presets.enumerated() {
            let metric = PersistedMetric(
                name: preset.name,
                kind: .manual,
                color: preset.color,
                sortOrder: idx
            )
            context.insert(metric)

            for offset in 0..<180 {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                let weekday = calendar.component(.weekday, from: date)
                let isWeekend = (weekday == 1 || weekday == 7)
                let dayMultiplier = isWeekend ? preset.weekendBias : preset.weekdayBias
                let recentMultiplier = offset < 14 ? preset.recentBoost : 1.0
                let raw = preset.curve(offset) * dayMultiplier * recentMultiplier
                let count = min(preset.cap, max(0, raw)).rounded()
                guard count > 0 else { continue }
                let key = SnapshotMetric.dateKey(for: date)
                let entry = PersistedManualEntry(metric: metric, dateKey: key, count: count)
                context.insert(entry)
            }
        }
        try? context.save()
        SyncCoordinator(context: context, integrations: .resolved()).rebuildManualOnly()
    }

    @MainActor
    static func clearAll(in context: ModelContext) {
        let descriptor = FetchDescriptor<PersistedMetric>()
        if let metrics = try? context.fetch(descriptor) {
            for metric in metrics {
                context.delete(metric)
            }
        }
        try? context.save()
        SyncCoordinator(context: context, integrations: .resolved()).rebuildManualOnly()
    }
}
#endif
