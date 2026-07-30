import Foundation

/// Settings synced via App Group UserDefaults so both the app and widget extension see the same value.
public enum SharedSettings {
    private static let suiteName = "group.io.github.user-416.widgets"
    private static let lastStravaRateLimitKey = "settings.lastStravaRateLimit"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    /// When set to a future date, indicates Strava is in a 429 cooldown until that time.
    /// Cleared (set to nil) when the cooldown expires or after a successful sync.
    public static var lastStravaRateLimit: Date? {
        get { defaults?.object(forKey: lastStravaRateLimitKey) as? Date }
        set {
            if let newValue {
                defaults?.set(newValue, forKey: lastStravaRateLimitKey)
            } else {
                defaults?.removeObject(forKey: lastStravaRateLimitKey)
            }
        }
    }
}
