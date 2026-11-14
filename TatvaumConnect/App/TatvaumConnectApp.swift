import UserNotifications
import SwiftUI

@main
struct TatvaumConnectApp: App {
    @State private var container = AppContainer()
    @Environment(\.scenePhase) private var phase

    init() { UNUserNotificationCenter.current().delegate = ThirdEyeNotificationDelegate.shared }

    var body: some Scene {
        WindowGroup {
            RootView(c: container)
                .preferredColorScheme(.dark)
                .tint(Cosmic.gold)
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .active:
                Task { await ThirdEyeNotifier.ensure(seed: container.thirdEye.seed) }  // keep next Monday's question current
                container.thirdEye.current()
                ThirdEyeWidgetBridge.publish(container.thirdEye)                     // and the widget's weeks ahead
            case .background: container.chat.save()
            default: break
            }
        }
    }
}
