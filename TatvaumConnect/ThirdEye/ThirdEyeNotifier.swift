import Foundation
import Observation
import UserNotifications

/// Set when a Third Eye notification is tapped; the app observes it and switches tab.
@MainActor @Observable
final class ThirdEyeRouter {
    static let shared = ThirdEyeRouter()
    static let thirdEyeTab = 2
    /// Tab the app should switch to; the app clears it once handled.
    var requestedTab: Int?
}

/// Install as `UNUserNotificationCenter.current().delegate` at launch.
final class ThirdEyeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ThirdEyeNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == ThirdEyeNotifier.id else { return }
        await MainActor.run { ThirdEyeRouter.shared.requestedTab = ThirdEyeRouter.thirdEyeTab }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

/// "👁 A new Third Eye question": a weekly repeating Monday-7:00 local notification.
enum ThirdEyeNotifier {
    static let id = "third-eye-weekly"
    private static var center: UNUserNotificationCenter { .current() }

    static func canNotify() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// Asks for permission (a no-op prompt if already decided) and returns whether we can notify.
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Schedules the repeating Monday notification carrying the next arriving question.
    /// Call on launch/foreground and after enabling: a repeating trigger can't change its text,
    /// so refreshing keeps it current. Does nothing without permission.
    static func ensure(seed: UInt64, now: Date = .now) async {
        guard await canNotify() else { return }
        let arrival = ThirdEye.nextArrival(now: now)
        let question = ThirdEye.questionFor(week: ThirdEye.weekStart(now: arrival), seed: seed)
        let content = UNMutableNotificationContent()
        content.title = "👁 A new Third Eye question"
        content.body = question + "\n\nSit with it this week ✦"
        content.sound = .default
        let when = Calendar.current.dateComponents([.weekday, .hour, .minute], from: arrival)
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Enable flow for the "Get a Monday nudge" card.
    @MainActor static func enable(store: ThirdEyeStore) async -> Bool {
        guard await requestAuthorization() else { return false }
        await ensure(seed: store.seed)
        return true
    }
}
