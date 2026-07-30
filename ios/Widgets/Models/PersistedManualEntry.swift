import Foundation
import SwiftData

@Model
final class PersistedManualEntry {
    var dateKey: String
    var count: Double
    var updatedAt: Date
    var metric: PersistedMetric?

    init(metric: PersistedMetric, dateKey: String, count: Double) {
        self.dateKey = dateKey
        self.count = count
        self.updatedAt = .now
        self.metric = metric
    }
}
