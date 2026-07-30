import SwiftUI

public struct Palette: Sendable {
    public let empty: Color
    public let l1: Color
    public let l2: Color
    public let l3: Color
    public let l4: Color

    public init(empty: Color, l1: Color, l2: Color, l3: Color, l4: Color) {
        self.empty = empty
        self.l1 = l1
        self.l2 = l2
        self.l3 = l3
        self.l4 = l4
    }

    public func color(for bucket: Int) -> Color {
        switch bucket {
        case 0: return empty
        case 1: return l1
        case 2: return l2
        case 3: return l3
        default: return l4
        }
    }
}

public extension Palette {
    static let githubGreen = Palette(
        empty: Color(hex: 0xebedf0),
        l1: Color(hex: 0x9be9a8),
        l2: Color(hex: 0x40c463),
        l3: Color(hex: 0x30a14e),
        l4: Color(hex: 0x216e39)
    )

    static let blue = Palette(
        empty: Color(hex: 0xebedf0),
        l1: Color(hex: 0x9ec5fe),
        l2: Color(hex: 0x4285f4),
        l3: Color(hex: 0x1a73e8),
        l4: Color(hex: 0x0d47a1)
    )

    static let purple = Palette(
        empty: Color(hex: 0xebedf0),
        l1: Color(hex: 0xd6bbfb),
        l2: Color(hex: 0xa371f7),
        l3: Color(hex: 0x8250df),
        l4: Color(hex: 0x4c1d95)
    )

    static let orange = Palette(
        empty: Color(hex: 0xebedf0),
        l1: Color(hex: 0xfed7aa),
        l2: Color(hex: 0xfb923c),
        l3: Color(hex: 0xea580c),
        l4: Color(hex: 0x9a3412)
    )

    static let pink = Palette(
        empty: Color(hex: 0xebedf0),
        l1: Color(hex: 0xfbcfe8),
        l2: Color(hex: 0xf472b6),
        l3: Color(hex: 0xdb2777),
        l4: Color(hex: 0x831843)
    )

    static func resolve(_ name: PaletteName) -> Palette {
        switch name {
        case .githubGreen: return .githubGreen
        case .blue: return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .pink: return .pink
        }
    }
}
