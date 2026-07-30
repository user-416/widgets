// Faithful Strava OAuth consent sheet (DEBUG only). Mirrors the real
// `https://www.strava.com/oauth/authorize` screen visually per B2 §2f:
// orange `#FC4C02` header, app card, "Welcome back, …", scope checkbox
// rows (required = locked-checked), Cancel + Authorize buttons,
// "Powered by Strava" footer.
//
// The sheet doesn't implement OAuth at all — it just calls back to the
// presenting flow on Authorize/Cancel. The flow then either calls
// `FakeStravaClient.authenticate` (which short-circuits to mint tokens)
// or surfaces the cancellation as `StravaError.userCancelled`.
#if DEBUG
import SwiftUI

struct FakeStravaConsentSheet: View {
    let appName: String
    let athleteFirstName: String
    let scopes: [Scope]
    var onAuthorize: () -> Void
    var onCancel: () -> Void

    @State private var isAuthorizing: Bool = false
    @State private var checkedScopes: Set<String> = []

    /// One requested OAuth scope row, with its display copy.
    struct Scope: Identifiable, Equatable {
        let id: String              // "activity:read"
        let copy: String            // "View data about your activities"
        let required: Bool
        let detail: String?         // optional sub-line under the row
    }

    /// Sensible defaults for a Widgets-style activity-read flow.
    static let widgetsDefaults: [Scope] = [
        Scope(
            id: "read",
            copy: "View data about your public profile",
            required: true,
            detail: nil
        ),
        Scope(
            id: "activity:read",
            copy: "View data about your activities",
            required: true,
            detail: "Including activities visible to followers"
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    appCard
                    welcomeLine
                    scopesSection
                    revokeNotice
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            footer
        }
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear {
            // Pre-check required + optional scopes (real Strava does the
            // same — every requested scope renders pre-checked).
            checkedScopes = Set(scopes.map(\.id))
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            stravaOrange
            HStack(spacing: 8) {
                stravaChevron
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.white)
                Text("STRAVA")
                    .font(.system(size: 18, weight: .heavy, design: .default))
                    .tracking(2)
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 4)
        }
        .frame(height: 56)
    }

    private var stravaChevron: some View {
        // Approximation of Strava's chevron mark — three stacked
        // chevrons. Real glyph is trademarked; this is a stylized proxy
        // that reads as "Strava-ish" without copying the actual logo.
        Path { p in
            p.move(to: CGPoint(x: 4, y: 16))
            p.addLine(to: CGPoint(x: 12, y: 4))
            p.addLine(to: CGPoint(x: 20, y: 16))
            p.move(to: CGPoint(x: 8, y: 20))
            p.addLine(to: CGPoint(x: 12, y: 14))
            p.addLine(to: CGPoint(x: 16, y: 20))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    // MARK: - App card

    private var appCard: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(
                    colors: [Color(red: 0.20, green: 0.78, blue: 0.40),
                             Color(red: 0.10, green: 0.52, blue: 0.30)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "square.grid.4x3.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 6) {
                Text("\(appName) would like to connect to your Strava account.")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.14, green: 0.14, blue: 0.16))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var welcomeLine: some View {
        Text("Welcome back, \(athleteFirstName).")
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(Color(red: 0.30, green: 0.30, blue: 0.32))
    }

    // MARK: - Scopes

    private var scopesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This application would like to:")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(red: 0.40, green: 0.40, blue: 0.42))
            ForEach(scopes) { scope in
                scopeRow(scope)
            }
        }
    }

    private func scopeRow(_ scope: Scope) -> some View {
        let isChecked = checkedScopes.contains(scope.id)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                guard !scope.required else { return }
                if isChecked {
                    checkedScopes.remove(scope.id)
                } else {
                    checkedScopes.insert(scope.id)
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(scope.required ? stravaOrange : Color(red: 0.6, green: 0.6, blue: 0.62), lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isChecked ? stravaOrange : Color.white)
                        )
                        .frame(width: 20, height: 20)
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(scope.required)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(scope.copy)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color(red: 0.14, green: 0.14, blue: 0.16))
                    if scope.required {
                        Text("(required)")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color(red: 0.50, green: 0.50, blue: 0.52))
                    }
                }
                if let detail = scope.detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.50, green: 0.50, blue: 0.52))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var revokeNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You can revoke access at any time at")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.47))
            Text("https://www.strava.com/settings/apps")
                .font(.system(size: 12))
                .foregroundStyle(stravaOrange)
        }
    }

    // MARK: - Footer (buttons + powered-by)

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.14, green: 0.14, blue: 0.16))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.85, green: 0.85, blue: 0.87), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAuthorizing)

                Button {
                    guard !isAuthorizing else { return }
                    isAuthorizing = true
                    onAuthorize()
                } label: {
                    HStack(spacing: 8) {
                        if isAuthorizing {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Authorize")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(stravaOrange)
                    )
                }
                .buttonStyle(.plain)
            }

            Text("Powered by Strava")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.55, green: 0.55, blue: 0.57))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color(red: 0.90, green: 0.90, blue: 0.92)),
            alignment: .top
        )
    }

    // MARK: - Constants

    /// Strava brand orange: `#FC4C02`.
    private var stravaOrange: Color {
        Color(red: 0xFC / 255.0, green: 0x4C / 255.0, blue: 0x02 / 255.0)
    }
}

#Preview {
    FakeStravaConsentSheet(
        appName: "Widgets",
        athleteFirstName: "Marianne",
        scopes: FakeStravaConsentSheet.widgetsDefaults,
        onAuthorize: {},
        onCancel: {}
    )
}
#endif
