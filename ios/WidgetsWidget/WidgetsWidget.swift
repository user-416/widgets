import WidgetKit
import SwiftUI

struct WidgetsWidget: Widget {
    let kind: String = "WidgetsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: MetricSelectionIntent.self,
            provider: Provider()
        ) { entry in
            HeatmapWidgetView(entry: entry)
        }
        .configurationDisplayName("KPI Grid")
        .description("Track a personal KPI as a GitHub-style contribution graph.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct WidgetsWidgetBundle: WidgetBundle {
    var body: some Widget {
        WidgetsWidget()
    }
}
