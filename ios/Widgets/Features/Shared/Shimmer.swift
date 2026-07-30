import SwiftUI

/// Subtle shimmer overlay used in place of `ProgressView()` while a sync is
/// running. A diagonal gradient translates left-to-right indefinitely, masked
/// to the modified view's shape so it never clips outside the heatmap or row.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.55),
                            Color.white.opacity(0),
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geo.size.width * 1.6)
                    .offset(x: phase * geo.size.width)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
            )
            .clipped()
            .task {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

extension View {
    /// Apply a left-to-right shimmer overlay. Use sparingly — only during
    /// active sync, never on idle content.
    func shimmer(_ active: Bool = true) -> some View {
        Group {
            if active { modifier(Shimmer()) } else { self }
        }
    }
}
