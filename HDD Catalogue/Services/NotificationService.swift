import Foundation
import UserNotifications

/// Manages macOS notifications for scan completion and drive events.
enum NotificationService {
    
    /// Request notification permission on app launch.
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    /// Notify when a scan completes.
    static func notifyScanComplete(driveName: String, projectCount: Int) {
        guard UserDefaults.standard.bool(forKey: "showNotifications") else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Scan Complete"
        content.body = "Found \(projectCount) projects on \(driveName)."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "scan-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
    
    /// Notify when a new drive is detected for the first time.
    static func notifyNewDrive(name: String) {
        guard UserDefaults.standard.bool(forKey: "showNotifications") else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "New Drive Detected"
        content.body = "\(name) has been connected and added to the catalogue."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "new-drive-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
    
    /// Notify when duplicates are found.
    static func notifyDuplicatesFound(count: Int) {
        guard UserDefaults.standard.bool(forKey: "showNotifications") else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Duplicates Detected"
        content.body = "AI found \(count) potential duplicate project\(count == 1 ? "" : "s") across your drives."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "duplicates-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
