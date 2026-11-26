import Foundation
import UserNotifications

/// Sideloaded builds get revoked, and a revocation takes the store with it.
/// This is the nudge that turns "I should back up at some point" into a
/// notification on the sixth day, before the seventh.
///
/// The clock starts at the first launch of an install. Revoking and reinstalling
/// resets the container, so the install date and the data age are the same thing
/// — which is exactly what the notification reports.
@MainActor
enum BackupReminder {
    static let installKey = "backup.installDate"
    static let lastBackupKey = "backup.lastBackupDate"
    static let enabledKey = "backup.remindersEnabled"
    static let identifier = "backup.reminder"
    static let intervalDays = 6

    static var installDate: Date {
        if let stored = UserDefaults.standard.object(forKey: installKey) as? Date {
            return stored
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: installKey)
        return now
    }

    static var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: lastBackupKey) as? Date
    }

    static func recordBackup(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastBackupKey)
        Task { await schedule(force: true) }
    }

    static var daysSinceInstall: Int {
        Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
    }

    /// Next sixth-day mark at or after now. Scheduling is idempotent: every
    /// launch replaces the pending request, so the reminder follows the install
    /// rather than drifting with the last time the app happened to run.
    static func schedule(force: Bool = false) async {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        guard enabled else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        // Never prompt from a launch-time code path: permission is requested in
        // Backup & restore, where the rider can see why.
        let granted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        guard granted else {
            RevertDiagnostics.log("backup.reminder skipped status=\(settings.authorizationStatus.rawValue)")
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let calendar = Calendar.current
        // The clock runs from whichever is newer: the install or the last real
        // backup, so a backup made this morning silences the reminder.
        let start = max(installDate, lastBackupDate ?? .distantPast)
        var fire = calendar.date(byAdding: .day, value: intervalDays, to: start) ?? Date().addingTimeInterval(6 * 86_400)
        while fire < Date() {
            fire = calendar.date(byAdding: .day, value: intervalDays, to: fire) ?? Date().addingTimeInterval(6 * 86_400)
        }

        let content = UNMutableNotificationContent()
        content.title = "Back up Revert before the app is revoked"
        content.sound = .default
        content.body = bodyText(anchor: start, fireDate: fire)
        content.userInfo = ["destination": "backup"]

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            let seconds = fire.timeIntervalSinceNow
            let daysAhead = Int((seconds / 86_400).rounded(.up))
            RevertDiagnostics.log("backup.reminder scheduled=\(daysAhead)d installDays=\(daysSinceInstall)")
        } catch {
            RevertDiagnostics.log("backup.reminder failed: \(error.localizedDescription)")
        }
    }

    private static func bodyText(anchor: Date, fireDate: Date) -> String {
        let days = max(0, Calendar.current.dateComponents([.day], from: anchor, to: fireDate).day ?? intervalDays)
        let unit = days == 1 ? "day" : "days"
        if lastBackupDate != nil {
            return "It has been \(days) \(unit) since your last Revert backup. Back up again from Settings → Data & privacy → Backup & restore."
        }
        return "It has been \(days) \(unit) since this install and no backup exists. Back up from Settings → Data & privacy → Backup & restore."
    }

    /// Requests authorization only from a UI action that explains the reason.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    #if DEBUG
    /// `-debugBackupReminder` fires in ten seconds so the notification can be
    /// checked on a device without waiting six days.
    static func scheduleDebugDemo() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let granted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        guard granted else {
            RevertDiagnostics.log("backup.reminder.debug permission=denied status=\(settings.authorizationStatus.rawValue)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Back up Revert before the app is revoked"
        content.sound = .default
        content.body = bodyText(anchor: max(installDate, lastBackupDate ?? .distantPast), fireDate: Date().addingTimeInterval(10))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier + ".debug",
                                                    content: content, trigger: trigger))
        RevertDiagnostics.log("backup.reminder.debug scheduled=10s")
        try? await Task.sleep(nanoseconds: 13_000_000_000)
        let delivered = await center.deliveredNotifications()
        let matches = delivered.filter { $0.request.identifier.hasPrefix(identifier) }
        RevertDiagnostics.log("backup.reminder.debug delivered=\(delivered.count) matching=\(matches.count)")
    }
    #endif
}
