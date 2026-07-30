import Foundation

public enum PaletteName: String, Codable, Sendable, CaseIterable, Identifiable {
    case githubGreen = "github-green"
    case blue
    case purple
    case orange
    case pink

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .githubGreen: return "GitHub Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .orange: return "Orange"
        case .pink: return "Pink"
        }
    }
}
