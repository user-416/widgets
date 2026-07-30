import SwiftUI
import SwiftData
import WidgetsShared

struct MetricRowView: View {
    let metric: PersistedMetric

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appContainer: AppContainerHolder
    @State private var refreshTick: Int = 0

    var body: some View {
        let snapshotMetric = makeSnapshotMetric()

        let palette = Palette.resolve(metric.color)
        let count = snapshotMetric.count(on: .now)
        let hasNoHistory = metric.manualEntries.isEmpty
        let showFirstTapCTA = metric.kind == .manual && count == 0 && hasNoHistory

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                // 28x28 tinted-background tile (matches AddMetric IntegrationCard treatment)
                Image(systemName: metric.kind.systemImageName)
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(palette.l3)
                    .frame(width: 28, height: 28)
                    .background(palette.l1.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text(metric.name)
                    .font(.headline)
                Spacer()
                if showFirstTapCTA {
                    // Inline CTA replaces the count for first-time manual metrics.
                    EmptyView()
                } else if count == 0 {
                    Text("No entries today")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatCount(count))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(palette.l3)
                            .monospacedDigit()
                        Text("today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if showFirstTapCTA {
                Button {
                    incrementToday()
                } label: {
                    Text("Tap to log your first one")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.l3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(palette.l1.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("firstTapCTA")
            } else {
                HeatmapView(metric: snapshotMetric, weeks: 13, cellSize: 9, cellSpacing: 2)
            }
        }
        .padding(.vertical, 4)
        .id(refreshTick)
        // TODO A3-Home chevron suppression: NavigationLink in List renders a chevron
        // by default; suppressing it cleanly requires switching the row to a button +
        // programmatic navigation, which is out of scope for this atomic commit.
    }

    private func incrementToday() {
        let key = SnapshotMetric.dateKey(for: .now)
        if let existing = metric.manualEntries.first(where: { $0.dateKey == key }) {
            existing.count += 1
            existing.updatedAt = .now
        } else {
            let new = PersistedManualEntry(metric: metric, dateKey: key, count: 1)
            context.insert(new)
        }
        try? context.save()
        SyncCoordinator(context: context, integrations: appContainer.container).rebuildManualOnly()
        refreshTick &+= 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func formatCount(_ value: Double) -> String {
        if value == value.rounded() { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }

    private func makeSnapshotMetric() -> SnapshotMetric {
        var days: [String: Double] = [:]
        for entry in metric.manualEntries {
            days[entry.dateKey, default: 0] += entry.count
        }
        return SnapshotMetric(
            id: metric.id,
            name: metric.name,
            kind: metric.kind,
            color: metric.color,
            thresholds: metric.thresholds,
            days: days
        )
    }

}
