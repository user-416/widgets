import Foundation

/// Resolves whether the app should use the in-process fake integration clients
/// instead of real network/HealthKit calls. Always `false` in RELEASE builds
/// (no Fake* type is even linked), and resolved once at process launch in
/// DEBUG so views and the SyncCoordinator see a stable value for the lifetime
/// of the process.
///
/// The resolved value can be flipped at runtime by the Settings → Debug
/// picker via `AppContainerHolder.refresh()`, which re-reads the manual
/// override and rebuilds the IntegrationContainer.
enum FakeMode {
    /// AppStorage key for the manual override. Values: `"auto"`, `"on"`, `"off"`.
    static let manualOverrideKey = "debug.fakeMode.manualOverride"

    #if DEBUG
    /// Cached at first access. Re-resolved when `AppContainerHolder.refresh()`
    /// is called.
    private static let storage = Storage()

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var cached: Bool?

        func read() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if let cached { return cached }
            let resolved = FakeMode.resolveAtLaunch()
            cached = resolved
            return resolved
        }

        func invalidate() {
            lock.lock(); defer { lock.unlock() }
            cached = nil
        }
    }

    static var isEnabled: Bool {
        storage.read()
    }

    /// Re-reads the manual override + credential state. Call this when the
    /// user flips the Settings → Debug toggle so the next IntegrationContainer
    /// resolution picks up the change.
    static func invalidateCache() {
        storage.invalidate()
    }

    static func resolveAtLaunch() -> Bool {
        let override = UserDefaults.standard.string(forKey: manualOverrideKey) ?? "auto"
        switch override {
        case "on":
            return true
        case "off":
            return false
        default:
            // Auto: fake when no real creds are wired up. A dev with real
            // Strava credentials gets the real path automatically; a fresh
            // checkout on the simulator gets fake data automatically.
            let hasStrava = IntegrationCredentials.Strava.tokens() != nil
            return !hasStrava
        }
    }
    #else
    static var isEnabled: Bool { false }
    static func invalidateCache() {}
    #endif
}
