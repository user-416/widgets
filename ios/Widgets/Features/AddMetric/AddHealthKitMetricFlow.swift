import SwiftUI
import SwiftData
import WidgetsShared

/// Consolidated "Add from Apple Health" flow.
///
/// Replaces the previous one-card-per-type pattern (Steps / Workouts as
/// separate gallery entries) with a single Apple-style entry point: pick
/// any subset of HealthKit-backed metrics, then request authorization
/// once for the union of sample types and create N PersistedMetric rows
/// in a single pass.
struct AddHealthKitMetricFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appContainer: AppContainerHolder
    @Query private var existingMetrics: [PersistedMetric]

    let onComplete: () -> Void

    @State private var selected: Set<MetricKind>
    @State private var phase: Phase = .selecting
    @State private var errorMessage: String?
    @State private var permissionDenied: Bool = false

    enum Phase {
        case selecting
        case requesting
        case denied
    }

    init(
        initialSelection: Set<MetricKind>? = nil,
        onComplete: @escaping () -> Void
    ) {
        self.onComplete = onComplete
        // Default = everything checked (matches the spec: "Both selected
        // by default"). Tests / future callers can override.
        let defaults = initialSelection ?? Set(AppleHealthSubtype.all.map(\.kind))
        _selected = State(initialValue: defaults)
    }

    var body: some View {
        NavigationStack {
            Group {
                if phase == .denied {
                    deniedView
                } else {
                    selectionView
                }
            }
            .navigationTitle("Add from Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if phase != .denied {
                    bottomBar
                }
            }
        }
    }

    // MARK: - Selection view

    private var selectionView: some View {
        Form {
            Section {
                ForEach(AppleHealthSubtype.all) { subtype in
                    subtypeRow(subtype)
                }
            } header: {
                Text("Choose what to track")
            } footer: {
                Text("Widgets reads these from the Health app to render your daily contribution graph.")
                    .font(.footnote)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func subtypeRow(_ subtype: AppleHealthSubtype) -> some View {
        let isSelected = selected.contains(subtype.kind)
        let isAlreadyAdded = existingMetrics.contains { $0.kind == subtype.kind && !$0.archived }
        return Button {
            toggle(subtype.kind)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: subtype.systemImage)
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(subtype.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(isAlreadyAdded ? "Already added" : subtype.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtype.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func toggle(_ kind: MetricKind) {
        if selected.contains(kind) {
            selected.remove(kind)
        } else {
            selected.insert(kind)
        }
    }

    // MARK: - Denied view

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Apple Health access denied")
                .font(.headline)
            Text("Widgets needs read access to Apple Health to chart your steps and workouts. Enable it in Settings → Privacy → Health → Widgets.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                openSettings()
            } label: {
                Text("Open Settings")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 220, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.githubGreen.l3)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Bottom bar

    private var bottomBarLabel: String {
        switch phase {
        case .requesting:
            return "Requesting…"
        case .selecting, .denied:
            let n = selected.count
            return n == 1 ? "Add 1 metric" : "Add \(n) metrics"
        }
    }

    private var bottomBarDisabled: Bool {
        switch phase {
        case .requesting: return true
        case .denied: return true
        case .selecting: return selected.isEmpty
        }
    }

    private var bottomBar: some View {
        Button(action: bottomBarAction) {
            HStack(spacing: 8) {
                if phase == .requesting {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(bottomBarLabel)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Palette.githubGreen.l3)
        .disabled(bottomBarDisabled)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func bottomBarAction() {
        switch phase {
        case .requesting, .denied: break
        case .selecting: requestAndCreate()
        }
    }

    // MARK: - Auth + create

    private func requestAndCreate() {
        guard !selected.isEmpty else { return }
        phase = .requesting
        errorMessage = nil
        let health = appContainer.container.health
        let toCreate = AppleHealthSubtype.all.filter { selected.contains($0.kind) }
        Task {
            do {
                let granted = try await health.requestAuthorization()
                guard granted else {
                    phase = .denied
                    return
                }
                createMetrics(toCreate)
            } catch HealthKitError.notAvailable {
                phase = .selecting
                errorMessage = "Apple Health isn't available on this device."
            } catch {
                phase = .selecting
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func createMetrics(_ subtypes: [AppleHealthSubtype]) {
        // Skip subtypes that are already added (un-archived) so re-running the
        // flow doesn't duplicate rows. Spec doesn't require this but it's the
        // natural Apple behavior — a user re-entering the flow expects "add
        // what's missing" rather than dupes.
        let existing = Set(existingMetrics.filter { !$0.archived }.map(\.kind))
        let baseOrder = (existingMetrics.map(\.sortOrder).max() ?? -1) + 1
        var inserted = 0
        for (offset, subtype) in subtypes.enumerated() where !existing.contains(subtype.kind) {
            let metric = PersistedMetric(
                name: subtype.title,
                kind: subtype.kind,
                color: subtype.defaultColor,
                sortOrder: baseOrder + offset
            )
            context.insert(metric)
            inserted += 1
        }
        try? context.save()

        if inserted > 0 {
            let coordinator = SyncCoordinator(context: context, integrations: appContainer.container)
            Task {
                await coordinator.rebuildSnapshot()
            }
        }

        onComplete()
    }
}

// MARK: - Color picker (shared with other flows)

struct ColorPalettePicker: View {
    @Binding var selected: PaletteName

    var body: some View {
        HStack(spacing: 12) {
            ForEach(PaletteName.allCases) { palette in
                Button {
                    selected = palette
                } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Palette.resolve(palette).l3)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if selected == palette {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.white)
                                    .font(.headline)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color: \(palette.displayName)")
                .accessibilityAddTraits(selected == palette ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color")
    }
}
