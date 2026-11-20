import Foundation
import UserNotifications

/// Presents Revert's own notifications while the app is in the foreground.
///
/// iOS suppresses banners for a foreground app unless a delegate says
/// otherwise, which would make the backup reminder invisible to anyone who
/// happens to have Revert open when it fires.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.userInfo["destination"] as? String == "backup" {
            // The flag covers a cold start (the tap launched the app); the
            // notification covers a tap while it is already running.
            UserDefaults.standard.set(true, forKey: "backup.openRequested")
            NotificationCenter.default.post(name: .revertOpenBackup, object: nil)
        }
        completionHandler()
    }
}
