import SwiftUI
import SwiftData
import WidgetsShared

/// Gallery shown when the user taps "Add metric". One card per integration
/// surface — Apple Health is one card that fans out to its sub-types in a
/// secondary sheet (see `AddHealthKitMetricFlow`).
struct AddMetricView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var existingMetrics: [PersistedMetric]
    @State private var selectedEntry: GalleryEntry?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(GalleryEntry.allCases) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            IntegrationCard(
                                entry: entry,
                                status: status(for: entry)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Add metric")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $selectedEntry) { entry in
                flow(for: entry)
            }
        }
    }

    @ViewBuilder
    private func flow(for entry: GalleryEntry) -> some View {
        switch entry {
        case .manual:
            AddManualMetricFlow(kind: .manual) { dismiss() }
        case .appleHealth:
            AddHealthKitMetricFlow { dismiss() }
        case .strava:
            AddStravaMetricFlow { dismiss() }
        case .toggl:
            AddTogglMetricFlow { dismiss() }
        }
    }

    private func status(for entry: GalleryEntry) -> IntegrationCard.Status {
        switch entry {
        case .manual:
            // Manual is always "available" — there's no auth state and no
            // single canonical "manual is connected" condition (you can have
            // many).
            return .available
        case .appleHealth:
            // Connected if any HealthKit-backed metric has been added.
            let kinds = Set(AppleHealthSubtype.all.map(\.kind))
            if existingMetrics.contains(where: { kinds.contains($0.kind) && !$0.archived }) {
                return .connected
            }
            return .available
        case .strava:
            if existingMetrics.contains(where: { $0.kind == .stravaActivityMinutes && !$0.archived }) {
                return .connected
            }
            if Configuration.workerBaseURL == nil {
                return .needsSetup
            }
            return .available
        case .toggl:
            if existingMetrics.contains(where: { $0.kind == .togglTrackedHours && !$0.archived }) {
                return .connected
            }
            return .available
        }
    }
}

/// Top-level entries surfaced in the Add Metric gallery. Distinct from
/// `MetricKind` because a single entry (Apple Health) can fan out to
/// multiple persisted kinds.
enum GalleryEntry: String, CaseIterable, Identifiable {
    case manual
    case appleHealth
    case strava
    case toggl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Manual"
        case .appleHealth: return "Apple Health"
        case .strava: return "Activity"
        case .toggl: return "Toggl Track"
        }
    }

    var subtitle: String {
        switch self {
        case .manual: return "Tap to log anything — calls, focus blocks, habits."
        case .appleHealth: return "Steps, workouts, and more from the Health app."
        case .strava: return "Activity minutes from Strava."
        case .toggl: return "Tracked hours per day from Toggl."
        }
    }

    var sourceLabel: String? {
        switch self {
        case .manual: return nil
        case .appleHealth: return "Apple Health"
        case .strava: return "Strava"
        case .toggl: return "Toggl Track"
        }
    }

    var systemImageName: String {
        switch self {
        case .manual: return "hand.tap"
        case .appleHealth: return "heart.text.square"
        case .strava: return "bolt.heart"
        case .toggl: return "clock.fill"
        }
    }
}

struct IntegrationCard: View {
    enum Status {
        case available, connected, needsSetup

        var label: String {
            switch self {
            case .available: "Add"
            case .connected: "Connected"
            case .needsSetup: "Needs setup"
            }
        }

        var tint: Color {
            switch self {
            case .available: .secondary
            case .connected: .green
            case .needsSetup: .orange
            }
        }
    }

    let entry: GalleryEntry
    let status: Status

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: entry.systemImageName)
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(iconBackground(for: entry))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Spacer()
                statusPill
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            if let source = entry.sourceLabel {
                Text(source)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(status.label)")
        .accessibilityHint(entry.subtitle)
    }

    private var statusPill: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.tint.opacity(0.12))
            .clipShape(Capsule())
    }

    /// Per-source brand tint for the icon tile background. Keeps the gallery
    /// reading as a curated set of integrations rather than identical pale
    /// tiles. (A2 design-review #6.)
    private func iconBackground(for entry: GalleryEntry) -> Color {
        switch entry {
        case .strava:
            // Strava brand orange (#FC4C02)
            return Color(red: 0.988, green: 0.298, blue: 0.012).opacity(0.15)
        case .appleHealth:
            // Apple Health red (#FA2D48)
            return Color(red: 0.980, green: 0.176, blue: 0.282).opacity(0.15)
        case .manual:
            // Widgets brand green
            return Palette.githubGreen.l1.opacity(0.4)
        case .toggl:
            // Toggl brand red (#E01E5A)
            return Color(red: 0.878, green: 0.118, blue: 0.353).opacity(0.15)
        }
    }
}
