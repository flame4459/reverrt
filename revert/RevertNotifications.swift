import Foundation

nonisolated extension Notification.Name {
    static let revertOpenIntent = Notification.Name("revert.openIntent")
    /// A backup reminder was tapped: show the backup screen wherever the app is.
    static let revertOpenBackup = Notification.Name("revert.openBackup")
}
