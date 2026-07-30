import Foundation
import WidgetsShared
import OSLog
import WidgetKit

enum SnapshotWriter {
    private static let logger = Logger(subsystem: "io.github.user-416.widgets", category: "SnapshotWriter")

    static func write(_ snapshot: Snapshot) {
        guard let url = AppGroup.snapshotURL else {
            logger.error("App Group container unavailable; check entitlement \(AppGroup.identifier)")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
            logger.info("Wrote snapshot (\(data.count) bytes, \(snapshot.metrics.count) metrics) to \(url.path)")
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            logger.error("Failed to write snapshot: \(error.localizedDescription)")
        }
    }

    static func read() -> Snapshot {
        guard let url = AppGroup.snapshotURL,
              let data = try? Data(contentsOf: url) else {
            return .empty
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Snapshot.self, from: data)) ?? .empty
    }
}
