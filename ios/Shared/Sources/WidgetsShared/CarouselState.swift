import Foundation

/// Per-user "currently displayed metric in the cycling widget" — App Group UserDefaults
/// so the widget extension and main app see the same value. Intentionally global (not
/// per-widget-instance) so cycling on any placed widget syncs the others.
public enum CarouselState {
    private static let suiteName = "group.io.github.user-416.widgets"
    private static let key = "widget.carousel.metricID"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    public static var metricID: String? {
        get { defaults?.string(forKey: key) }
        set { defaults?.set(newValue, forKey: key) }
    }

    /// Advances the carousel by `direction` (+1 or -1) wrapping around the snapshot's
    /// metric list. Falls back to the first metric if state is missing.
    public static func advance(by direction: Int, in snapshot: Snapshot) {
        guard !snapshot.metrics.isEmpty else { return }
        let ids = snapshot.metrics.map(\.id)
        let currentIndex = metricID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let count = ids.count
        let nextIndex = ((currentIndex + direction) % count + count) % count
        metricID = ids[nextIndex]
    }
}
