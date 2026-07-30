#if DEBUG
import SwiftUI
import WidgetsShared

/// Renders the heatmap at the same dimensions used by the widget extension so we can
/// visually verify (and snapshot-test) what each widget family will look like, without
/// needing to add the widget to the home screen via Simulator UI.
struct WidgetPreviewView: View {
    let metric: SnapshotMetric

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                preview(title: "Small (systemSmall)", size: CGSize(width: 158, height: 158)) {
                    smallContent
                }
                preview(title: "Medium (systemMedium)", size: CGSize(width: 338, height: 158)) {
                    mediumContent
                }
                preview(title: "Lock screen (accessoryRectangular)", size: CGSize(width: 172, height: 76)) {
                    accessoryContent
                }
            }
            .padding()
        }
        .navigationTitle("Widget preview")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("widgetPreviewScroll")
    }

    private func preview<Content: View>(title: String, size: CGSize, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(width: size.width, height: size.height)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.tertiary, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(metric.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(metric.count(on: .now)))")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            HeatmapView(metric: metric, weeks: 13, cellSize: 9, cellSpacing: 2)
            Spacer(minLength: 0)
        }
        .padding(8)
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(metric.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(metric.totalLastYear()))")
                    .font(.headline)
                    .monospacedDigit()
                Text("yr")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HeatmapView(metric: metric, weeks: 24, cellSize: 11, cellSpacing: 2)
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var accessoryContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            HeatmapView(metric: metric, weeks: 13, cellSize: 7, cellSpacing: 1)
        }
        .padding(8)
    }
}
#endif
