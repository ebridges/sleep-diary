import SwiftUI

/// The dark night palette from docs/design.md.
enum Theme {
    static let background = Color(hex: 0x0E1430)
    static let card = Color(hex: 0x18204A)
    static let cardRaised = Color(hex: 0x222B5E)
    static let line = Color(hex: 0x2E3874)
    static let text = Color(hex: 0xECEFFA)
    static let secondary = Color(hex: 0xAAB2D4)
    static let accent = Color(hex: 0xF4B860)
    static let onAccent = Color(hex: 0x1B1404)
    static let success = Color(hex: 0x7FD6A8)

    static let rem = Color(hex: 0xB6C2FF)
    static let core = Color(hex: 0x6F87F2)
    static let deep = Color(hex: 0x4458D0)
    static let awake = accent

    static func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake: return awake
        case .rem: return rem
        case .core, .unspecified: return core
        case .deep: return deep
        }
    }

    static let headingFont = Font.system(size: 28, weight: .semibold)
    static let cardTitleFont = Font.system(size: 17, weight: .semibold)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
