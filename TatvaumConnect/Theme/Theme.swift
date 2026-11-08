import SwiftUI

extension Color {
    /// `0xAARRGGBB` like the Android palette.
    init(argb: UInt32) {
        self.init(.sRGB,
                  red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
                  blue: Double(argb & 0xFF) / 255, opacity: Double(argb >> 24) / 255)
    }
}

/// Cosmic palette (always dark, gold accent, translucent indigo panels).
enum Cosmic {
    static let spaceBg = Color(argb: 0xFF05060D)
    static let panel = Color(argb: 0xD10E1020)
    static let panelSolid = Color(argb: 0xFF0E1020)
    static let panelBorder = Color(argb: 0x2EA0AAFF)
    static let starText = Color(argb: 0xFFE6E8FF)
    static let muted = Color(argb: 0xFF9AA0C8)
    static let faint = Color(argb: 0xFF6F75A0)
    static let gold = Color(argb: 0xFFF5C66B)
    static let amber = Color(argb: 0xFFE08A4F)
    static let onGold = Color(argb: 0xFF1A1020)
    static let goldSoft = Color(argb: 0xFFF3DCAE)
    static let lavender = Color(argb: 0xFFA0AAFF)
    static let constellation = Color(argb: 0xFF8FB4FF)
    static let retro = Color(argb: 0xFFFF8A8A)
    static let fire = Color(argb: 0xFFFF7A59)
    static let earth = Color(argb: 0xFF7BD88F)
    static let air = Color(argb: 0xFFF2E27A)
    static let water = Color(argb: 0xFF5FA8FF)
    static let warning = Color(argb: 0xFFF59E0B)
    static let success = Color(argb: 0xFF6FE0A8)
    static let error = Color(argb: 0xFFFF6B8A)
    static let surfaceVariant = Color(argb: 0xFF161931)

    static let goldGradient = LinearGradient(colors: [gold, amber], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let body = Color(argb: 0xFFD6D9F5)
}
