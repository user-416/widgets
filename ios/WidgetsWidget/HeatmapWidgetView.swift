import SwiftUI
import WidgetKit
import WidgetsShared

struct HeatmapWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MetricEntry

    var body: some View {
        if let metric = entry.metric {
            content(for: metric)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private func content(for metric: SnapshotMetric) -> some View {
        switch family {
        case .systemSmall:
            smallContent(metric: metric)
        case .systemMedium:
            mediumContent(metric: metric)
        case .accessoryRectangular:
            accessoryRectangularContent(metric: metric)
        default:
            mediumContent(metric: metric)
        }
    }

    private func smallContent(metric: SnapshotMetric) -> some View {
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
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }

    private func mediumContent(metric: SnapshotMetric) -> some View {
        let snapshot = SnapshotReader.read()
        let total = snapshot.metrics.count
        let index = snapshot.metrics.firstIndex(where: { $0.id == metric.id }) ?? 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if total > 1 {
                    Button(intent: CyclePreviousMetricIntent()) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Previous metric")
                }
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
                if total > 1 {
                    Button(intent: CycleNextMetricIntent()) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Next metric")
                }
            }
            if total > 1 {
                positionDots(current: index, total: total, accent: Palette.resolve(metric.color).l3)
                    .accessibilityLabel("Metric \(index + 1) of \(total)")
            }
            HeatmapView(metric: metric, weeks: 24, cellSize: 11, cellSpacing: 2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }

    private func positionDots(current: Int, total: Int, accent: Color) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<min(total, 8), id: \.self) { idx in
                Capsule()
                    .fill(idx == current ? accent : Color.secondary.opacity(0.3))
                    .frame(width: idx == current ? 14 : 5, height: 5)
            }
            if total > 8 {
                Text("+\(total - 8)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var hasMultipleMetrics: Bool {
        SnapshotReader.read().metrics.count > 1
    }

    private func accessoryRectangularContent(metric: SnapshotMetric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            HeatmapView(metric: metric, weeks: 13, cellSize: 7, cellSpacing: 1)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.grid.4x3.fill")
                .font(.title2)
            Text("No metric")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Open Widgets to add one.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }
}
