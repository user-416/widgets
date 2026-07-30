import AppIntents
import SwiftUI
import WidgetKit
import WidgetsShared

struct MetricEntry: TimelineEntry {
    let date: Date
    let metric: SnapshotMetric?
    let configuration: MetricSelectionIntent
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MetricEntry {
        MetricEntry(date: .now, metric: .preview, configuration: MetricSelectionIntent())
    }

    /// Each metric in the user's snapshot becomes a pre-configured tile in the widget
    /// gallery. Tapping one places that metric directly on the home screen — no Edit
    /// Widget step. Adding 2+ then dragging them on top of each other creates a Widget
    /// Stack with native vertical-swipe navigation between metrics.
    func recommendations() -> [AppIntentRecommendation<MetricSelectionIntent>] {
        let snapshot = SnapshotReader.read()
        return snapshot.metrics.map { metric in
            var intent = MetricSelectionIntent()
            intent.metric = MetricEntity(
                id: metric.id,
                name: metric.name,
                kindRaw: metric.kind.rawValue,
                color: metric.color.rawValue
            )
            return AppIntentRecommendation(
                intent: intent,
                description: Text(metric.name)
            )
        }
    }

    func snapshot(for configuration: MetricSelectionIntent, in context: Context) async -> MetricEntry {
        MetricEntry(
            date: .now,
            metric: resolveMetric(for: configuration),
            configuration: configuration
        )
    }

    func timeline(for configuration: MetricSelectionIntent, in context: Context) async -> Timeline<MetricEntry> {
        let metric = resolveMetric(for: configuration)
        let now = Date()
        var entries: [MetricEntry] = []
        let interval: TimeInterval = 60 * 60
        for hour in 0..<24 {
            let date = now.addingTimeInterval(Double(hour) * interval)
            entries.append(MetricEntry(date: date, metric: metric, configuration: configuration))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func resolveMetric(for configuration: MetricSelectionIntent) -> SnapshotMetric? {
        let snapshot = SnapshotReader.read()
        if let cycledID = CarouselState.metricID,
           let match = snapshot.metrics.first(where: { $0.id == cycledID }) {
            return match
        }
        if let chosenId = configuration.metric?.id,
           let match = snapshot.metrics.first(where: { $0.id == chosenId }) {
            return match
        }
        return snapshot.metrics.first
    }
}
