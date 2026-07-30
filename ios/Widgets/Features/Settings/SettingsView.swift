import SwiftUI
import SwiftData
import WidgetKit
import WidgetsShared

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appContainer: AppContainerHolder
    @Query private var allMetrics: [PersistedMetric]
    @State private var showStravaDisconnect = false
    @State private var stravaConnected: Bool = false
    @State private var showingWidgetOnboarding = false
    @State private var showingAdd: AddTarget?

    #if DEBUG
    @AppStorage("debug.fakeMode.manualOverride") private var fakeOverride: String = "auto"
    @State private var showAdvancedDebug: Bool = false
    @State private var showClearAllConfirm: Bool = false
    #endif

    enum AddTarget: Identifiable {
        case healthKit, strava, manual
        var id: String { String(describing: self) }
    }

    var body: some View {
        Form {
            Section("Integrations") {
                integrationRow(.healthKit)
                integrationRow(.strava)
                integrationRow(.manual)
            }

            Section("Widgets") {
                Button {
                    showingWidgetOnboarding = true
                } label: {
                    Label("How to add a widget", systemImage: "square.grid.4x3.fill")
                        .foregroundStyle(.primary)
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
            }

            #if DEBUG
            Section("Debug") {
                DisclosureGroup("Show advanced", isExpanded: $showAdvancedDebug) {
                    Picker("Fake mode", selection: $fakeOverride) {
                        Text("Auto").tag("auto")
                        Text("Force ON").tag("on")
                        Text("Force OFF").tag("off")
                    }
                    .accessibilityIdentifier("fakeModeOverridePicker")
                    .onChange(of: fakeOverride) { _, _ in
                        appContainer.refresh()
                        Task {
                            await SyncCoordinator(
                                context: context,
                                integrations: appContainer.container
                            ).rebuildSnapshot()
                        }
                    }
                    Text(fakeModeStatusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    NavigationLink("Fake scenarios") {
                        FakeScenariosView()
                            .environmentObject(appContainer)
                    }
                    .accessibilityIdentifier("fakeScenariosLink")

                    Button("Seed sample data") {
                        SampleData.seed(into: context)
                    }
                    Button("Clear all metrics", role: .destructive) {
                        showClearAllConfirm = true
                    }
                    .accessibilityIdentifier("clearAllMetrics")
                    NavigationLink("Preview widgets") {
                        WidgetPreviewView(metric: previewMetric ?? .preview)
                    }
                    .accessibilityIdentifier("widgetPreviewLink")

                    Button("Inject 90 days of fake step samples") {
                        Task { await HealthKitDebug.injectSampleSteps() }
                    }
                    .accessibilityIdentifier("injectHealthSamples")
                }
            }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Read Keychain on appear instead of @State init —
            // hitting the Keychain at view-construction time can fire on
            // background threads during view diffing (B3 §5.2 hazard).
            stravaConnected = IntegrationCredentials.Strava.tokens() != nil
        }
        .alert("Disconnect Strava?", isPresented: $showStravaDisconnect) {
            Button("Disconnect", role: .destructive) {
                try? IntegrationCredentials.Strava.disconnect()
                stravaConnected = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing Strava metrics will keep their cached data but stop updating until you reconnect.")
        }
        #if DEBUG
        .alert("Clear all metrics?", isPresented: $showClearAllConfirm) {
            Button("Delete", role: .destructive) {
                SampleData.clearAll(in: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all your metrics and entries. Cannot be undone.")
        }
        #endif
        .sheet(isPresented: $showingWidgetOnboarding) {
            WidgetOnboardingView()
        }
        .sheet(item: $showingAdd) { target in
            switch target {
            case .healthKit:
                AddHealthKitMetricFlow { showingAdd = nil }
            case .strava:
                AddStravaMetricFlow { showingAdd = nil }
            case .manual:
                AddManualMetricFlow(kind: .manual) { showingAdd = nil }
            }
        }
    }

    @ViewBuilder
    private func integrationRow(_ target: AddTarget) -> some View {
        let info = integrationInfo(target)
        Button {
            switch target {
            case .strava where info.isConnected:
                showStravaDisconnect = true
            default:
                showingAdd = target
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: info.icon)
                    .frame(width: 22)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(info.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge(info.status)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(info.name): \(info.status.label)")
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(_ status: IntegrationStatus) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private struct IntegrationInfo {
        var name: String
        var icon: String
        var status: IntegrationStatus
        var statusDescription: String
        var isConnected: Bool { status == .connected }
    }

    private enum IntegrationStatus: Equatable {
        case connected, needsSetup, notConfigured
        var color: Color {
            switch self {
            case .connected: .green
            case .needsSetup: .orange
            case .notConfigured: Color.secondary.opacity(0.5)
            }
        }
        var label: String {
            switch self {
            case .connected: "Connected"
            case .needsSetup: "Needs setup"
            case .notConfigured: "Not configured"
            }
        }
    }

    private func integrationInfo(_ target: AddTarget) -> IntegrationInfo {
        switch target {
        case .healthKit:
            let connected = allMetrics.contains { $0.kind == .healthkitSteps || $0.kind == .healthkitWorkoutsMinutes }
            return .init(name: "Apple Health",
                         icon: "heart.text.square",
                         status: connected ? .connected : .notConfigured,
                         statusDescription: connected ? "Steps and workouts syncing" : "Tap to add steps or workouts")
        case .strava:
            let connected = stravaConnected
            let needsConfig = Configuration.stravaWorkerBaseURL == nil
            // In fake mode the connection "is" the demo, so surface a positive
            // state. When fake mode is OFF and the worker URL is missing we
            // show neutral grey + a friendly "setup pending" subtitle rather
            // than dev-speak about Info.plist.
            let fakeOn = FakeMode.isEnabled
            let status: IntegrationStatus
            let description: String
            if connected {
                status = .connected
                description = "Activity minutes syncing"
            } else if fakeOn {
                status = .connected
                description = "Connected (demo)"
            } else if needsConfig {
                status = .notConfigured
                description = "Strava setup pending"
            } else {
                status = .notConfigured
                description = "Tap to connect"
            }
            return .init(name: "Strava",
                         icon: "bolt.heart",
                         status: status,
                         statusDescription: description)
        case .manual:
            let connected = allMetrics.contains { $0.kind == .manual }
            return .init(name: "Manual",
                         icon: "hand.tap",
                         status: connected ? .connected : .notConfigured,
                         statusDescription: connected ? "Tap-to-log metrics active" : "Tap to add a counter")
        }
    }

    var connectedCount: Int {
        [AddTarget.healthKit, .strava, .manual]
            .filter { integrationInfo($0).isConnected }
            .count
    }

    #if DEBUG
    private var previewMetric: WidgetsShared.SnapshotMetric? {
        let snapshot = SnapshotWriter.read()
        return snapshot.metrics.first
    }

    /// Human-readable summary of the resolved fake-mode state. Reads
    /// `FakeMode.isEnabled` (which respects the manual override + creds)
    /// and the override key directly so we can show the user both pieces
    /// of information.
    private var fakeModeStatusLabel: String {
        let on = FakeMode.isEnabled
        let suffix: String
        switch fakeOverride {
        case "on": suffix = "forced"
        case "off": suffix = "forced"
        default: suffix = "auto"
        }
        return "Currently: \(on ? "ON" : "OFF") (\(suffix))"
    }
    #endif

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

#if DEBUG
/// Sub-screen for tweaking which `FakeScenario` case each fake client
/// produces. Persists two String AppStorage keys read by
/// `IntegrationContainer.fake` (computed) at build time. After every
/// pick we call `AppContainerHolder.refresh()` so the next
/// SyncCoordinator instantiation picks up the new scenario; we also
/// trigger an immediate snapshot rebuild so heatmaps update live.
struct FakeScenariosView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appContainer: AppContainerHolder

    @AppStorage("debug.fakeMode.stravaScenario") private var stravaScenario: String = "happy"
    @AppStorage("debug.fakeMode.healthScenario") private var healthScenario: String = "happy"

    var body: some View {
        Form {
            Section("Strava") {
                Picker("Scenario", selection: $stravaScenario) {
                    Text("Happy").tag("happy")
                    Text("Rate limited").tag("rateLimited")
                    Text("Expired mid-paginate").tag("expiredMidPaginate")
                    Text("Denied").tag("denied")
                    Text("Empty").tag("empty")
                }
                .accessibilityIdentifier("fakeStravaScenarioPicker")
                .onChange(of: stravaScenario) { _, _ in scenarioChanged() }
            }
            Section("Health") {
                Picker("Scenario", selection: $healthScenario) {
                    Text("Happy").tag("happy")
                    Text("Denied").tag("denied")
                    Text("Empty").tag("empty")
                }
                .accessibilityIdentifier("fakeHealthScenarioPicker")
                .onChange(of: healthScenario) { _, _ in scenarioChanged() }
            }
            Section {
                Text("Scenarios only take effect when fake mode is ON. Toggle behavior is restored on the previous screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Fake scenarios")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scenarioChanged() {
        appContainer.refresh()
        Task {
            await SyncCoordinator(
                context: context,
                integrations: appContainer.container
            ).rebuildSnapshot()
        }
    }
}
#endif
