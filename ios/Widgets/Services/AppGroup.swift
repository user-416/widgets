import Foundation

enum AppGroup {
    static let identifier = "group.io.github.user-416.widgets"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("snapshot.json")
    }
}
