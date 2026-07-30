import Foundation

public enum MetricKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case manual
    case healthkitSteps = "healthkit_steps"
    case healthkitWorkoutsMinutes = "healthkit_workouts_minutes"
    case stravaActivityMinutes = "strava_activity_minutes"
    case healthkitSleep = "healthkit_sleep"
    case healthkitActiveEnergy = "healthkit_active_energy"
    case healthkitMindfulMinutes = "healthkit_mindful_minutes"
    case healthkitHRV = "healthkit_hrv"
    case healthkitRestingHR = "healthkit_resting_hr"
    case healthkitBodyMass = "healthkit_body_mass"
    case togglTrackedHours = "toggl_tracked_hours"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .healthkitSteps: return "Steps"
        case .healthkitWorkoutsMinutes: return "Workouts"
        case .stravaActivityMinutes: return "Strava"
        case .healthkitSleep: return "Sleep"
        case .healthkitActiveEnergy: return "Active Energy"
        case .healthkitMindfulMinutes: return "Mindful Minutes"
        case .healthkitHRV: return "HRV"
        case .healthkitRestingHR: return "Resting HR"
        case .healthkitBodyMass: return "Body Mass"
        case .togglTrackedHours: return "Toggl"
        }
    }

    public var defaultThresholds: [Double] {
        switch self {
        case .manual: return [1, 2, 4, 7]
        case .healthkitSteps: return [1, 5_000, 10_000, 15_000]
        case .healthkitWorkoutsMinutes: return [1, 15, 30, 60]
        case .stravaActivityMinutes: return [1, 30, 60, 90]
        case .healthkitSleep: return [1, 360, 420, 480]       // minutes: 6h, 7h, 8h
        case .healthkitActiveEnergy: return [1, 200, 400, 600] // kcal
        case .healthkitMindfulMinutes: return [1, 5, 10, 20]   // minutes
        case .healthkitHRV: return [1, 20, 40, 60]             // ms
        case .healthkitRestingHR: return [1, 50, 60, 70]       // bpm
        case .healthkitBodyMass: return [1, 60, 75, 90]        // kg
        case .togglTrackedHours: return [1, 2, 4, 8]           // hours
        }
    }

    public var defaultName: String {
        switch self {
        case .manual: return "Manual"
        case .healthkitSteps: return "Steps"
        case .healthkitWorkoutsMinutes: return "Workouts"
        case .stravaActivityMinutes: return "Strava"
        case .healthkitSleep: return "Sleep"
        case .healthkitActiveEnergy: return "Active Energy"
        case .healthkitMindfulMinutes: return "Mindful Minutes"
        case .healthkitHRV: return "HRV"
        case .healthkitRestingHR: return "Resting HR"
        case .healthkitBodyMass: return "Body Mass"
        case .togglTrackedHours: return "Toggl"
        }
    }

    public var systemImageName: String {
        switch self {
        case .manual: return "hand.tap"
        case .healthkitSteps: return "figure.walk"
        case .healthkitWorkoutsMinutes: return "dumbbell"
        case .stravaActivityMinutes: return "bolt.heart"
        case .healthkitSleep: return "bed.double.fill"
        case .healthkitActiveEnergy: return "flame.fill"
        case .healthkitMindfulMinutes: return "brain.head.profile"
        case .healthkitHRV: return "waveform.path.ecg"
        case .healthkitRestingHR: return "heart.fill"
        case .healthkitBodyMass: return "scalemass.fill"
        case .togglTrackedHours: return "clock.fill"
        }
    }
}
