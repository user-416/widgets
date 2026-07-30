import Foundation

/// Bundle of integration clients used by `SyncCoordinator` and the Add flows.
/// Constructed once at the app root and (in DEBUG) flipped between
/// `.production` and `.fake` based on `FakeMode.isEnabled`.
struct IntegrationContainer: Sendable {
    let strava: any StravaAPI
    let health: any HealthDataReading
    let toggl: any TogglAPI

    static let production = IntegrationContainer(
        strava: LiveStravaClient(),
        health: LiveHealthClient(),
        toggl: LiveTogglClient()
    )

    #if DEBUG
    /// Computed so that scenario knobs from Settings → Debug ("Fake
    /// scenarios") are picked up fresh every time the container is
    /// rebuilt via `AppContainerHolder.refresh()`. Reads two string
    /// AppStorage keys — `debug.fakeMode.{strava,health}Scenario` —
    /// and maps them onto `FakeScenario` enum cases. Unknown / missing
    /// values fall back to `.happy`.
    static var fake: IntegrationContainer {
        let defaults = UserDefaults.standard
        let stravaScenario = parseStravaScenario(
            defaults.string(forKey: "debug.fakeMode.stravaScenario")
        )
        let healthScenario = parseHealthScenario(
            defaults.string(forKey: "debug.fakeMode.healthScenario")
        )
        return IntegrationContainer(
            strava: FakeStravaClient(scenario: stravaScenario),
            health: FakeHealthClient(scenario: healthScenario),
            toggl: LiveTogglClient()
        )
    }

    static func resolved() -> IntegrationContainer {
        FakeMode.isEnabled ? .fake : .production
    }

    private static func parseStravaScenario(_ raw: String?) -> FakeScenario.Strava {
        switch raw {
        case "rateLimited": return .rateLimited
        case "expiredMidPaginate": return .expiredMidPaginate
        case "denied": return .denied
        case "empty": return .empty
        default: return .happy
        }
    }

    private static func parseHealthScenario(_ raw: String?) -> FakeScenario.Health {
        switch raw {
        case "denied": return .denied
        case "empty": return .empty
        default: return .happy
        }
    }
    #else
    static func resolved() -> IntegrationContainer { .production }
    #endif
}
