import SwiftUI
import WidgetsShared

struct WidgetOnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    VStack(spacing: 12) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            stepCard(number: index + 1, step: step)
                        }
                    }
                    bottomTip
                }
                .padding()
            }
            .navigationTitle("Add to home screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("Got it")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.regularMaterial)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.4x3.fill")
                .font(.system(size: 56))
                .foregroundStyle(Palette.githubGreen.l3)
                .padding(.top, 8)
            Text("See your KPI without opening the app")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Pin a Widgets widget to your home or lock screen. Long-press lets you swap which metric it shows.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private struct Step {
        let symbol: String
        let title: String
        let description: String
    }

    private var steps: [Step] {
        [
            Step(
                symbol: "hand.tap.fill",
                title: "Long-press your home screen",
                description: "Hold an empty area for about 1.5 seconds until app icons jiggle."
            ),
            Step(
                symbol: "plus.rectangle.on.rectangle",
                title: "Tap Edit \u{2192} Add Widget",
                description: "Top-left of the screen, then choose Add Widget from the popup."
            ),
            Step(
                symbol: "magnifyingglass",
                title: "Find KPI Grid",
                description: "Scroll or use the search field. Tap to open it."
            ),
            Step(
                symbol: "checkmark.circle.fill",
                title: "Pick a metric \u{2192} Add Widget",
                description: "Each of your metrics shows up as a pre-configured tile. Tap one, hit Add Widget, then Done."
            ),
            Step(
                symbol: "rectangle.stack.fill",
                title: "(Optional) Stack to swipe",
                description: "Add a few widgets, drag one onto another. iOS turns them into a stack you can swipe through vertically."
            )
        ]
    }

    private func stepCard(number: Int, step: Step) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Palette.githubGreen.l1.opacity(0.5))
                    .frame(width: 36, height: 36)
                Text("\(number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.githubGreen.l4)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.headline)
                Text(step.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: step.symbol)
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var bottomTip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Lock screen too", systemImage: "lock.iphone")
                .font(.subheadline.weight(.semibold))
            Text("Settings \u{2192} Wallpaper \u{2192} Customize Lock Screen \u{2192} tap a widget slot \u{2192} KPI Grid.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    WidgetOnboardingView()
}
