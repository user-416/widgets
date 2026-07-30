import Foundation

enum BackfillQueue {
    private static let secondsPerDay: TimeInterval = 86_400

    static func enqueue(metricID: String, daysBack: Int = 90) {
        let now = Date()
        let nextStart = now.addingTimeInterval(-Double(daysBack) * secondsPerDay)
        let defaults = UserDefaults.standard
        defaults.set(nextStart, forKey: nextStartKey(metricID))
        defaults.set(now, forKey: targetKey(metricID))
    }

    static func nextChunk(metricID: String, chunkDays: Int = 7) -> (start: Date, end: Date)? {
        let defaults = UserDefaults.standard
        guard
            let nextStart = defaults.object(forKey: nextStartKey(metricID)) as? Date,
            let target = defaults.object(forKey: targetKey(metricID)) as? Date
        else {
            return nil
        }
        guard nextStart < target else { return nil }

        let proposedEnd = nextStart.addingTimeInterval(Double(chunkDays) * secondsPerDay)
        let end = min(proposedEnd, target)
        return (nextStart, end)
    }

    static func markChunkComplete(metricID: String, end: Date) {
        let advanced = end.addingTimeInterval(1)
        UserDefaults.standard.set(advanced, forKey: nextStartKey(metricID))
    }

    static func clear(metricID: String) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: nextStartKey(metricID))
        defaults.removeObject(forKey: targetKey(metricID))
    }

    private static func nextStartKey(_ metricID: String) -> String {
        "backfill.\(metricID).nextStart"
    }

    private static func targetKey(_ metricID: String) -> String {
        "backfill.\(metricID).target"
    }
}
