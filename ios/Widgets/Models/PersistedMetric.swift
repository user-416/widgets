import Foundation
import SwiftData
import WidgetsShared

@Model
final class PersistedMetric {
    @Attribute(.unique) var id: String
    var name: String
    var kindRaw: String
    var colorRaw: String
    var thresholds: [Double]
    var sortOrder: Int
    var archived: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PersistedManualEntry.metric)
    var manualEntries: [PersistedManualEntry] = []

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: MetricKind,
        color: PaletteName = .githubGreen,
        thresholds: [Double]? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.colorRaw = color.rawValue
        self.thresholds = thresholds ?? kind.defaultThresholds
        self.sortOrder = sortOrder
        self.archived = false
        self.createdAt = .now
    }

    var kind: MetricKind {
        get { MetricKind(rawValue: kindRaw) ?? .manual }
        set { kindRaw = newValue.rawValue }
    }

    var color: PaletteName {
        get { PaletteName(rawValue: colorRaw) ?? .githubGreen }
        set { colorRaw = newValue.rawValue }
    }
}
