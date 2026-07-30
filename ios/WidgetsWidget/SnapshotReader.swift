import Foundation
import WidgetsShared

enum SnapshotReader {
    static let appGroupIdentifier = "group.io.github.user-416.widgets"

    static func read() -> Snapshot {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("snapshot.json"),
              let data = try? Data(contentsOf: url) else {
            return .empty
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Snapshot.self, from: data)) ?? .empty
    }
}
