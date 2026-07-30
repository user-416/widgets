import AppIntents
import WidgetKit
import WidgetsShared

/// Tappable in the widget — advances the global carousel forward.
struct CycleNextMetricIntent: AppIntent {
    static let title: LocalizedStringResource = "Next metric"
    static let description = IntentDescription("Show the next metric in the widget.")
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        let snapshot = SnapshotReader.read()
        CarouselState.advance(by: 1, in: snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "WidgetsWidget")
        return .result()
    }
}

/// Tappable in the widget — advances the global carousel backward.
struct CyclePreviousMetricIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous metric"
    static let description = IntentDescription("Show the previous metric in the widget.")
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        let snapshot = SnapshotReader.read()
        CarouselState.advance(by: -1, in: snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "WidgetsWidget")
        return .result()
    }
}
