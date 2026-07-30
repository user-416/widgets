import Foundation
import SwiftUI

/// Observable holder for the resolved `IntegrationContainer`. Injected at
/// the app root via `.environmentObject(...)` so any view can pull the
/// current container with `@EnvironmentObject AppContainerHolder`.
///
/// `refresh()` is called by the Settings → Debug toggle when the user flips
/// the manual override. It re-resolves `FakeMode` and swaps the underlying
/// container; `@Published` ensures dependent views re-render.
@MainActor
final class AppContainerHolder: ObservableObject {
    @Published private(set) var container: IntegrationContainer

    /// Process-wide singleton so non-SwiftUI call sites
    /// (Settings toggle, manual ad-hoc rebuilds) can reach the holder.
    /// SwiftUI views should prefer `@EnvironmentObject`.
    static let shared = AppContainerHolder()

    init(container: IntegrationContainer = .resolved()) {
        self.container = container
    }

    /// Re-resolve the container after the user flips the fake-mode toggle.
    /// In RELEASE this is effectively a no-op since `.resolved()` is always
    /// `.production`.
    func refresh() {
        #if DEBUG
        FakeMode.invalidateCache()
        #endif
        container = .resolved()
    }
}
