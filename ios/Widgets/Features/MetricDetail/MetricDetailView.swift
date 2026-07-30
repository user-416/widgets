import SwiftUI
import SwiftData
import WidgetsShared

struct MetricDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appContainer: AppContainerHolder
    @Bindable var metric: PersistedMetric
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var refreshTick: Int = 0
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var stravaCooldownTick: Int = 0

    var body: some View {
        let _ = refreshTick
        let _ = stravaCooldownTick
        let snapshot = makeSnapshotMetric()

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summaryCard(snapshot: snapshot)

                heatmapCard(snapshot: snapshot)
                    .shimmer(isSyncing)

                if metric.kind == .manual {
                    incrementCard()
                } else {
                    syncCard()
                }

                thresholdsCard()
            }
            .padding()
        }
        .navigationTitle(metric.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let syncError {
                syncErrorBanner(message: syncError)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(), value: syncError)
        .onChange(of: syncError) { _, newValue in
            scheduleAutoDismiss(active: newValue != nil)
        }
        .task {
            // Tick the Strava cooldown countdown roughly every 60s so the subtitle stays accurate.
            while !Task.isCancelled {
                stravaCooldownTick &+= 1
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    private func syncErrorBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                retrySync()
            } label: {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.95))
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    private func scheduleAutoDismiss(active: Bool) {
        autoDismissTask?.cancel()
        guard active else {
            autoDismissTask = nil
            return
        }
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                syncError = nil
            }
        }
    }

    private func retrySync() {
        // Cancel the auto-dismiss timer so the user's explicit retry isn't blown away.
        autoDismissTask?.cancel()
        autoDismissTask = nil
        syncError = nil
        syncNow()
    }

    private func syncCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Source")
                        .font(.headline)
                    Text(sourceDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let cooldownText = stravaCooldownSubtitle {
                        Text(cooldownText)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button {
                    syncNow()
                } label: {
                    HStack {
                        if isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isSyncing ? "Syncing…" : "Sync now")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSyncing)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var sourceDescription: String {
        switch metric.kind {
        case .manual: return "Manual entries"
        case .healthkitSteps: return "Apple Health — Steps"
        case .healthkitWorkoutsMinutes: return "Apple Health — Workouts"
        case .healthkitSleep: return "Apple Health — Sleep"
        case .healthkitActiveEnergy: return "Apple Health — Active Energy"
        case .healthkitMindfulMinutes: return "Apple Health — Mindful Minutes"
        case .healthkitHRV: return "Apple Health — HRV"
        case .healthkitRestingHR: return "Apple Health — Resting Heart Rate"
        case .healthkitBodyMass: return "Apple Health — Body Mass"
        case .stravaActivityMinutes: return "Strava — activity minutes"
        case .togglTrackedHours: return "Toggl Track — tracked hours"
        }
    }

    private func syncNow() {
        isSyncing = true
        syncError = nil
        let container = appContainer.container
        let beforeCooldown = SharedSettings.lastStravaRateLimit
        Task {
            await SyncCoordinator(context: context, integrations: container).rebuildSnapshot()
            isSyncing = false
            // Surface a sync error toast if Strava just hit a rate limit during this sync,
            // or if a previously-set cooldown is still active and this metric is Strava.
            if metric.kind == .stravaActivityMinutes,
               let until = SharedSettings.lastStravaRateLimit,
               until > .now,
               beforeCooldown != until {
                syncError = "Strava is rate-limited. Try again later."
            }
            stravaCooldownTick &+= 1
        }
    }

    /// Subtitle shown under the source label when Strava is in a 429 cooldown window.
    /// Returns nil for non-Strava metrics or when the cooldown has expired.
    private var stravaCooldownSubtitle: String? {
        guard metric.kind == .stravaActivityMinutes else { return nil }
        guard let until = SharedSettings.lastStravaRateLimit, until > .now else { return nil }
        let remaining = until.timeIntervalSinceNow
        let minutes = max(1, Int((remaining / 60.0).rounded(.up)))
        return "Rate limited — retry in \(minutes)m"
    }

    private func summaryCard(snapshot: SnapshotMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Int(snapshot.totalLastYear())) total")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("in the last year")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func heatmapCard(snapshot: SnapshotMetric) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HeatmapView(metric: snapshot, weeks: 53, cellSize: 11, cellSpacing: 2)
                    .padding(.horizontal, 4)
            }
            HStack {
                Text("Less")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { bucket in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.resolve(metric.color).color(for: bucket))
                        .frame(width: 11, height: 11)
                }
                Text("More")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func incrementCard() -> some View {
        let key = SnapshotMetric.dateKey(for: .now)
        let entry = entry(for: key)
        let count = entry?.count ?? 0

        return VStack(spacing: 16) {
            Text("Today")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button {
                    decrement(dateKey: key)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 36))
                }
                .buttonStyle(.plain)
                .foregroundStyle(count > 0 ? Color.accentColor : Color.gray.opacity(0.5))
                .disabled(count <= 0)
                .accessibilityIdentifier("decrementButton")

                Spacer()
                Text("\(Int(count))")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("todayCount")
                Spacer()

                Button {
                    increment(dateKey: key)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("incrementButton")
            }
            Text("Tap + each time you do this. The square fills in for today.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func thresholdsCard() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Thresholds")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { bucket in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.resolve(metric.color).color(for: bucket))
                            .frame(width: 24, height: 24)
                        Text(thresholdLabel(for: bucket))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func thresholdLabel(for bucket: Int) -> String {
        let t = metric.thresholds
        guard t.count >= 4 else { return "" }
        switch bucket {
        case 0: return "0"
        case 1: return "<\(format(t[1]))"
        case 2: return "<\(format(t[2]))"
        case 3: return "<\(format(t[3]))"
        default: return "≥\(format(t[3]))"
        }
    }

    private func format(_ value: Double) -> String {
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

    private func entry(for dateKey: String) -> PersistedManualEntry? {
        metric.manualEntries.first { $0.dateKey == dateKey }
    }

    private func increment(dateKey: String) {
        if let existing = entry(for: dateKey) {
            existing.count += 1
            existing.updatedAt = .now
        } else {
            let new = PersistedManualEntry(metric: metric, dateKey: dateKey, count: 1)
            context.insert(new)
        }
        try? context.save()
        SyncCoordinator(context: context, integrations: appContainer.container).rebuildManualOnly()
        refreshTick &+= 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func decrement(dateKey: String) {
        guard let existing = entry(for: dateKey), existing.count > 0 else { return }
        existing.count -= 1
        existing.updatedAt = .now
        if existing.count <= 0 {
            context.delete(existing)
        }
        try? context.save()
        SyncCoordinator(context: context, integrations: appContainer.container).rebuildManualOnly()
        refreshTick &+= 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
