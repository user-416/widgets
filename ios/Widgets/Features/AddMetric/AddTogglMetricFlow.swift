import SwiftUI
import SwiftData
import WidgetsShared

/// Add-metric flow for Toggl Track. User pastes their API token from
/// track.toggl.com → Profile → API Token. No OAuth — just Basic auth.
///
/// Phases:
///   1. `.entry`    — token input + validate button
///   2. `.validating` — spinner while validateToken() is in-flight
///   3. `.valid`    — green checkmark, name/color pickers, "Add metric" CTA
struct AddTogglMetricFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appContainer: AppContainerHolder

    let onComplete: () -> Void

    @State private var token: String = ""
    @State private var name: String = "Toggl"
    @State private var color: PaletteName = .blue
    @State private var phase: Phase = .entry
    @State private var errorMessage: String?

    enum Phase {
        case entry
        case validating
        case valid
    }

    // Toggl brand red (#E01E5A)
    private var togglRed: Color {
        Color(red: 0.878, green: 0.118, blue: 0.353)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if phase == .valid {
                        validCard
                        nameCard
                        colorCard
                    } else {
                        tokenCard
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
            Text("TOGGL TRACK")
                .font(.system(.subheadline, design: .default, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(togglRed)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("Add Toggl Track")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Token input

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("API Token")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Paste your API token from track.toggl.com → Profile → API Token.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                SecureField("32-character API token", text: $token)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    if let pasted = UIPasteboard.general.string {
                        token = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Text("Paste")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Valid / Name / Color

    private var validCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.title3)
            Text("Token verified")
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
            TextField("Toggl, Focus hours, …", text: $name)
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

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Bottom CTA bar

    private var bottomBarLabel: String {
        switch phase {
        case .entry: return "Validate token"
        case .validating: return "Validating…"
        case .valid: return "Add metric"
        }
    }

    private var bottomBarDisabled: Bool {
        switch phase {
        case .entry: return token.trimmingCharacters(in: .whitespaces).isEmpty
        case .validating: return true
        case .valid: return name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func bottomBarAction() {
        switch phase {
        case .entry: validate()
        case .validating: break
        case .valid: create()
        }
    }

    private var bottomBar: some View {
        Button(action: bottomBarAction) {
            HStack(spacing: 8) {
                if phase == .validating {
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
        .tint(phase == .valid ? Palette.githubGreen.l3 : togglRed)
        .disabled(bottomBarDisabled)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: - Logic

    private func validate() {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        phase = .validating
        errorMessage = nil

        Task {
            do {
                let client = TogglClient(token: trimmed)
                let valid = try await client.validateToken()
                if valid {
                    // Store immediately on success so LiveTogglClient can use it.
                    try? IntegrationCredentials.Toggl.store(trimmed)
                    phase = .valid
                } else {
                    phase = .entry
                    errorMessage = "That token didn't work. Make sure you copied the API token (32 hex chars), not your password."
                }
            } catch {
                phase = .entry
                errorMessage = "Network error: \(error.localizedDescription)"
            }
        }
    }

    private func create() {
        let metric = PersistedMetric(
            name: name.trimmingCharacters(in: .whitespaces),
            kind: .togglTrackedHours,
            color: color
        )
        context.insert(metric)
        try? context.save()

        let coordinator = SyncCoordinator(context: context, integrations: appContainer.container)
        Task {
            await coordinator.rebuildSnapshot()
        }

        onComplete()
    }
}
