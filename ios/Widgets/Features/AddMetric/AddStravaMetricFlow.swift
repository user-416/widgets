import SwiftUI
import SwiftData
import WidgetsShared
import AuthenticationServices

struct AddStravaMetricFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appContainer: AppContainerHolder

    let onComplete: () -> Void

    @State private var name: String = "Strava"
    @State private var color: PaletteName = .githubGreen
    @State private var phase: Phase = .intro
    @State private var errorMessage: String?
    @State private var alreadyConnected: Bool = false
    #if DEBUG
    @State private var showFakeConsent: Bool = false
    @State private var pendingWorkerURL: URL?
    #endif

    enum Phase {
        case intro
        case authenticating
        case connected
    }

    /// Strava brand orange (#FC4C02). Per Strava brand guidelines, the
    /// "Connect with Strava" button uses this exact color with white wordmark.
    /// Same hex as the Fakes/FakeStravaConsentSheet uses, but defined locally
    /// — the new entry screen does NOT import or share code with that fake.
    private var stravaOrange: Color {
        Color(red: 0xFC / 255.0, green: 0x4C / 255.0, blue: 0x02 / 255.0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if phase == .connected {
                        connectedCard
                        nameCard
                        colorCard
                    } else {
                        previewCopy
                        // A2 #4 originally placed an inline "Connect with Strava"
                        // brand button above the trust copy as a focal CTA. The
                        // bottom safe-area bar (A2 #11) already renders the same
                        // orange CTA, so showing both stacks two identical-looking
                        // orange buttons on a sparse screen — a high-severity
                        // visual defect surfaced in QA. The inline duplicate is
                        // dropped here; the bottom bar remains the single primary
                        // action. (See `bottomBar` below.)
                        trustCopy
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Read Keychain on appear instead of @State init (B3 §5.2 hazard).
                alreadyConnected = IntegrationCredentials.Strava.tokens() != nil
                if alreadyConnected {
                    phase = .connected
                }
            }
            #if DEBUG
            .sheet(isPresented: $showFakeConsent) {
                FakeStravaConsentSheet(
                    appName: "Widgets",
                    athleteFirstName: "Marianne",
                    scopes: FakeStravaConsentSheet.widgetsDefaults,
                    onAuthorize: { handleFakeConsent(authorized: true) },
                    onCancel: { handleFakeConsent(authorized: false) }
                )
                .interactiveDismissDisabled(true)
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STRAVA")
                .font(.system(.subheadline, design: .default, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(stravaOrange)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("Connect Strava")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Preview / trust copy

    private var previewCopy: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.right.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("You'll see a Strava login screen → tap Authorize → come back here automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Inline brand button. The bottom CTA bar duplicates this action so
    /// the button is reachable both as a focal in-form element (with the
    /// Strava brand styling) and via the persistent bottom-bar pattern
    /// shared across all Add* flows. Tapping either path starts the same
    /// `connect()` flow. (Documented choice per A2 #4.)
    private var connectButton: some View {
        Button {
            connect()
        } label: {
            HStack(spacing: 10) {
                if phase == .authenticating {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text("Connect with Strava")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(stravaOrange)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(phase == .authenticating)
    }

    private var trustCopy: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Widgets only reads your activities. Disconnect any time at strava.com/settings/apps.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Connected / Name / Color

    private var connectedCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.title3)
            Text("Strava connected")
                .font(.headline)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Strava, Runs, …", text: $name)
                .textInputAutocapitalization(.sentences)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ColorPalettePicker(selected: $color)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Bottom CTA bar

    private var bottomBarLabel: String {
        switch phase {
        case .connected: return "Add metric"
        case .authenticating: return "Connecting…"
        case .intro: return "Connect with Strava"
        }
    }

    private var bottomBarDisabled: Bool {
        switch phase {
        case .connected: return name.trimmingCharacters(in: .whitespaces).isEmpty
        case .authenticating: return true
        case .intro: return false
        }
    }

    private func bottomBarAction() {
        switch phase {
        case .connected: create()
        case .authenticating: break
        case .intro: connect()
        }
    }

    private var bottomBar: some View {
        Button(action: bottomBarAction) {
            HStack(spacing: 8) {
                if phase == .authenticating {
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
        .tint(phase == .connected ? Palette.githubGreen.l3 : stravaOrange)
        .disabled(bottomBarDisabled)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: - Logic

    private func connect() {
        #if DEBUG
        if FakeMode.isEnabled {
            // Fake mode: present the in-process consent sheet instead of
            // going through `ASWebAuthenticationSession`. The sheet's
            // Authorize/Cancel callbacks drive `phase` and tokens. We
            // pass a placeholder worker URL since the fake `authenticate`
            // ignores it.
            pendingWorkerURL = Configuration.stravaWorkerBaseURL
                ?? URL(string: "https://fake.invalid")
            errorMessage = nil
            showFakeConsent = true
            return
        }
        #endif

        guard let workerURL = Configuration.stravaWorkerBaseURL else {
            // In fake mode this branch is unreachable (handled above), so we
            // only surface the developer-speak when actually live and
            // misconfigured — addressing the A2 review note that fake users
            // were seeing this confusing string.
            errorMessage = "Strava isn't configured for this build. Set STRAVA_WORKER_BASE_URL in Info.plist to your deployed Worker URL."
            return
        }
        phase = .authenticating
        errorMessage = nil
        let strava = appContainer.container.strava
        Task {
            guard let anchor = activeAnchor() else {
                phase = .intro
                errorMessage = "Couldn't find a window to present authentication."
                return
            }
            do {
                let tokens = try await strava.authenticate(
                    presentationAnchor: anchor,
                    workerBaseURL: workerURL
                )
                try IntegrationCredentials.Strava.store(tokens)
                phase = .connected
            } catch StravaClient.StravaError.userCancelled {
                phase = .intro
            } catch {
                phase = .intro
                errorMessage = friendlyMessage(for: error)
            }
        }
    }

    #if DEBUG
    private func handleFakeConsent(authorized: Bool) {
        showFakeConsent = false
        guard authorized else {
            // Match the live path's user-cancelled UX.
            phase = .intro
            errorMessage = nil
            return
        }
        let workerURL = pendingWorkerURL ?? URL(string: "https://fake.invalid")!
        phase = .authenticating
        errorMessage = nil
        let strava = appContainer.container.strava
        Task {
            guard let anchor = activeAnchor() else {
                phase = .intro
                errorMessage = "Couldn't find a window to present authentication."
                return
            }
            do {
                let tokens = try await strava.authenticate(
                    presentationAnchor: anchor,
                    workerBaseURL: workerURL
                )
                try IntegrationCredentials.Strava.store(tokens)
                phase = .connected
            } catch StravaClient.StravaError.userCancelled {
                phase = .intro
            } catch {
                phase = .intro
                errorMessage = friendlyMessage(for: error)
            }
        }
    }
    #endif

    private func friendlyMessage(for error: any Error) -> String {
        if let strava = error as? StravaClient.StravaError {
            switch strava {
            case .userCancelled: return "Cancelled."
            case .oauthError(let msg): return "OAuth error: \(msg)"
            case .networkError: return "Network error reaching Strava."
            case .rateLimited: return "Strava rate-limited. Try again in a few minutes."
            case .invalidResponse: return "Unexpected response from Strava."
            case .stateMismatch: return "Couldn't verify the Strava callback. Please try connecting again."
            }
        }
        return error.localizedDescription
    }

    private func create() {
        let metric = PersistedMetric(
            name: name.trimmingCharacters(in: .whitespaces),
            kind: .stravaActivityMinutes,
            color: color
        )
        context.insert(metric)
        try? context.save()

        BackfillQueue.enqueue(metricID: metric.id, daysBack: 90)

        let coordinator = SyncCoordinator(context: context, integrations: appContainer.container)
        Task {
            await coordinator.rebuildSnapshot()
        }

        onComplete()
    }

    @MainActor
    private func activeAnchor() -> ASPresentationAnchor? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow }
    }
}
