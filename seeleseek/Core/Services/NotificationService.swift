import UserNotifications
import AppKit
import os

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.seeleseek", category: "Notifications")

    /// Reference to settings — set once from AppState.init
    var settings: SettingsState?

    private override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                self.logger.error("Notification auth failed: \(error.localizedDescription)")
            } else {
                self.logger.info("Notification auth granted: \(granted)")
            }
        }
    }

    /// Called from ActivityLog.log() — decides whether to post a system notification
    func handleActivityEvent(type: ActivityLog.EventType, title: String, detail: String?) {
        guard let settings, settings.enableNotifications else { return }
        if settings.notifyOnlyInBackground && NSApplication.shared.isActive { return }

        switch type {
        case .downloadCompleted:
            guard settings.notifyDownloads else { return }
            post(title: "Download Complete", body: detail ?? title)

        case .uploadCompleted:
            guard settings.notifyUploads else { return }
            post(title: "Upload Complete", body: detail ?? title)

        case .chatMessage:
            guard settings.notifyPrivateMessages else { return }
            post(title: title, body: detail)

        default:
            return
        }
    }

    private func post(title: String, body: String?, categoryIdentifier: String = "default") {
        let content = UNMutableNotificationContent()
        content.title = title
        if let body {
            content.body = body
        }
        if settings?.notificationSound == true {
            let selected = settings?.selectedNotificationSound ?? .default
            switch selected {
            case .default:
                content.sound = .default
            default:
                content.sound = UNNotificationSound(named: UNNotificationSoundName(selected.rawValue))
            }
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                self.logger.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when the app is in the foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
