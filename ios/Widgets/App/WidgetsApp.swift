import SwiftUI
import SwiftData

@main
struct WidgetsApp: App {
    let modelContainer: ModelContainer
    @StateObject private var appContainer = AppContainerHolder.shared

    init() {
        do {
            let schema = Schema([PersistedMetric.self, PersistedManualEntry.self])
            let inMemory = ProcessInfo.processInfo.arguments.contains("--reset-state-for-test")
            if inMemory {
                // Reset the AppStorage keys that gate empty-state UX so each
                // UI test starts from a clean Welcome screen. SwiftData itself
                // is reset by isStoredInMemoryOnly, but UserDefaults persists
                // across launches on the simulator.
                let d = UserDefaults.standard
                for key in [
                    "widget.onboarding.seen",
                    "home.quickStart.completed",
                    "home.quickStart.healthKitDenied",
                    "debug.fakeMode.manualOverride",
                    "debug.fakeMode.stravaScenario",
                    "debug.fakeMode.healthScenario",
                ] {
                    d.removeObject(forKey: key)
                }
                // Also wipe stored Strava credentials so each UI test starts
                // with no integrations connected. (Keychain persists across
                // simulator launches independent of SwiftData.)
                try? IntegrationCredentials.Strava.disconnect()
            }
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)]
            )
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .modelContainer(modelContainer)
                .environmentObject(appContainer)
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--seed-sample-data") {
                        await MainActor.run {
                            SampleData.seed(into: modelContainer.mainContext)
                        }
                    }
                    #endif
                }
        }
    }
}
