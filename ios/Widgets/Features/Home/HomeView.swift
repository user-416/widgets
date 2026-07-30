import SwiftUI
import SwiftData
import WidgetsShared

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appContainer: AppContainerHolder
    @Query(sort: [SortDescriptor(\PersistedMetric.sortOrder), SortDescriptor(\PersistedMetric.createdAt)])
    private var metrics: [PersistedMetric]
    @State private var showingAdd = false
    @State private var showingWidgetOnboarding = false
    @State private var quickStartRunning = false
    @State private var quickStartOutcome: QuickStartFlow.Outcome?
    @AppStorage("widget.onboarding.seen") private var widgetOnboardingSeen: Bool = false
    @AppStorage("home.quickStart.completed") private var quickStartCompleted: Bool = false
    @AppStorage("home.quickStart.healthKitDenied") private var healthKitDeniedBanner: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if metrics.isEmpty {
                    emptyState
                } else {
                    metricList
                }
            }
            .navigationTitle(metrics.isEmpty ? "" : "Widgets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .fontWeight(.semibold)
                    }
                    .accessibilityIdentifier("addMetricNavButton")
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .fontWeight(.semibold)
                    }
                    .accessibilityIdentifier("settingsNavLink")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddMetricView()
            }
            .sheet(isPresented: $showingWidgetOnboarding) {
                WidgetOnboardingView()
                    .onDisappear { widgetOnboardingSeen = true }
            }
        }
        .onAppear {
            let container = appContainer.container
            Task { await SyncCoordinator(context: context, integrations: container).rebuildSnapshot() }
        }
        .onChange(of: metrics.count) { oldValue, newValue in
            // Trigger the widget onboarding the first time the user finishes adding a metric.
            if newValue > oldValue, !widgetOnboardingSeen {
                showingWidgetOnboarding = true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 80)
            VStack(spacing: 16) {
                Image(systemName: "square.grid.4x3.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Palette.githubGreen.l3)
                Text(quickStartCompleted ? "No metrics yet" : "Welcome to Widgets")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(quickStartCompleted
                     ? "Add your first KPI to start filling in the grid."
                     : "Adds steps, workouts, and a daily counter.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if !quickStartCompleted {
                    Button {
                        runQuickStart()
                    } label: {
                        HStack {
                            if quickStartRunning {
                                ProgressView().controlSize(.small).tint(.white)
                            }
                            Text(quickStartRunning ? "Setting up…" : "Quick start")
                        }
                        .font(.headline)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(quickStartRunning)
                    .padding(.top, 8)
                    .accessibilityIdentifier("quickStartButton")

                    Button("Or add a custom metric") {
                        showingAdd = true
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.githubGreen.l3)
                    .padding(.top, 6)
                } else {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add metric", systemImage: "plus")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                    .accessibilityIdentifier("emptyStateAddButton")
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runQuickStart() {
        quickStartRunning = true
        let container = appContainer.container
        Task { @MainActor in
            let outcome = await QuickStartFlow(context: context, integrations: container).run()
            quickStartOutcome = outcome
            healthKitDeniedBanner = (outcome == .manualOnly)
            quickStartCompleted = true
            // Suppress the post-add WidgetOnboarding sheet for Quick Start —
            // it's too much for a first-tap flow. User can find it via Settings.
            widgetOnboardingSeen = true
            quickStartRunning = false
        }
    }

    private var connectedIntegrationsCount: Int {
        var count = 0
        if metrics.contains(where: { $0.kind == .manual && !$0.archived }) { count += 1 }
        if metrics.contains(where: { ($0.kind == .healthkitSteps || $0.kind == .healthkitWorkoutsMinutes) && !$0.archived }) { count += 1 }
        if IntegrationCredentials.Strava.tokens() != nil { count += 1 }
        return count
    }

    private var metricList: some View {
        List {
            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "link.circle.fill")
                            .foregroundStyle(connectedIntegrationsCount == 0 ? .secondary : Palette.githubGreen.l3)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(connectedIntegrationsCount) of 3 integrations connected")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(connectedIntegrationsCount == 3 ? "All set" : "Manage in Settings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityHint("Manage integrations in Settings")
            }

            if healthKitDeniedBanner {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.text.square")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect Apple Health for steps & workouts")
                                .font(.subheadline.weight(.medium))
                            Text("Tap to add HealthKit metrics from Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Dismiss") {
                            healthKitDeniedBanner = false
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            ForEach(metrics) { metric in
                NavigationLink {
                    MetricDetailView(metric: metric)
                } label: {
                    MetricRowView(metric: metric)
                }
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            context.delete(metrics[index])
        }
        try? context.save()
        SyncCoordinator(context: context, integrations: appContainer.container).rebuildManualOnly()
    }
}
