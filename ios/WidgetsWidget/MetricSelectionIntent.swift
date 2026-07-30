import AppIntents
import WidgetsShared

struct MetricSelectionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Metric"
    static let description = IntentDescription("Pick which metric to display.")

    @Parameter(title: "Metric")
    var metric: MetricEntity?
}

struct MetricEntity: AppEntity, Identifiable {
    var id: String
    var name: String
    var kindRaw: String
    var color: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")
    static let defaultQuery = MetricQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct MetricQuery: EntityQuery {
    func entities(for identifiers: [MetricEntity.ID]) async throws -> [MetricEntity] {
        snapshotEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [MetricEntity] {
        snapshotEntities()
    }

    func defaultResult() async -> MetricEntity? {
        snapshotEntities().first
    }

    private func snapshotEntities() -> [MetricEntity] {
        SnapshotReader.read().metrics.map { metric in
            MetricEntity(
                id: metric.id,
                name: metric.name,
                kindRaw: metric.kind.rawValue,
                color: metric.color.rawValue
            )
        }
    }
}
