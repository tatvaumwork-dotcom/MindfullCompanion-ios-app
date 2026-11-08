import SwiftUI

@main
struct TatvaumConnectApp: App {
    var body: some Scene {
        WindowGroup {
            CosmicBackground { Text("Tatvaum Connect").foregroundStyle(Cosmic.gold) }
                .preferredColorScheme(.dark)
                .tint(Cosmic.gold)
        }
    }
}
