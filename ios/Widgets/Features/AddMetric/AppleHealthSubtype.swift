import Foundation
import WidgetsShared

/// One row in the "Add from Apple Health" multi-select sheet.
///
/// To add a new HealthKit-backed metric (e.g. Sleep, Heart Rate, Active
/// Calories) the only required edits are:
///   1. Add a new `MetricKind` case in `WidgetsShared.MetricKind`
///   2. Add a corresponding entry to `AppleHealthSubtype.all` below
///   3. Wire it through `HealthKitReader.requestAuthorization` so the
///      union of HK sample types covers the new case, and add the
///      backfill query in `SyncCoordinator`.
/// No new SwiftUI files needed.
struct AppleHealthSubtype: Identifiable, Hashable {
    let kind: MetricKind
    let title: String
    let subtitle: String
    let systemImage: String
    let defaultColor: PaletteName

    var id: MetricKind { kind }

    /// Catalogue of Apple Health sub-types surfaced in the Add flow.
    /// Order here defines the order in the multi-select sheet.
    static let all: [AppleHealthSubtype] = [
        AppleHealthSubtype(
            kind: .healthkitSteps,
            title: "Steps",
            subtitle: "Daily step count",
            systemImage: "figure.walk",
            defaultColor: .blue
        ),
        AppleHealthSubtype(
            kind: .healthkitWorkoutsMinutes,
            title: "Workouts",
            subtitle: "Total workout minutes per day",
            systemImage: "dumbbell",
            defaultColor: .orange
        ),
        AppleHealthSubtype(
            kind: .healthkitSleep,
            title: "Sleep",
            subtitle: "Minutes asleep per night (wake-up day)",
            systemImage: "bed.double.fill",
            defaultColor: .purple
        ),
        AppleHealthSubtype(
            kind: .healthkitActiveEnergy,
            title: "Active Energy",
            subtitle: "Kilocalories burned per day",
            systemImage: "flame.fill",
            defaultColor: .orange
        ),
        AppleHealthSubtype(
            kind: .healthkitMindfulMinutes,
            title: "Mindful Minutes",
            subtitle: "Total mindfulness session minutes per day",
            systemImage: "brain.head.profile",
            defaultColor: .blue
        ),
        AppleHealthSubtype(
            kind: .healthkitHRV,
            title: "HRV",
            subtitle: "Heart rate variability average (ms)",
            systemImage: "waveform.path.ecg",
            defaultColor: .pink
        ),
        AppleHealthSubtype(
            kind: .healthkitRestingHR,
            title: "Resting Heart Rate",
            subtitle: "Average resting heart rate (BPM)",
            systemImage: "heart.fill",
            defaultColor: .pink
        ),
        AppleHealthSubtype(
            kind: .healthkitBodyMass,
            title: "Body Mass",
            subtitle: "Most recent weight reading per day (kg)",
            systemImage: "scalemass.fill",
            defaultColor: .githubGreen
        ),
    ]
}
