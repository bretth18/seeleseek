import Accessibility
import AppKit

/// Posts VoiceOver announcements for asynchronous events. A non-visual
/// user cannot see spinners, progress bars, or badges. Announcements
/// supply this data as speech.
///
/// Announcements are independent of system notifications. They occur
/// when notifications are off, because they do nothing unless
/// VoiceOver is on.
@MainActor
final class VoiceOverAnnouncer {
    static let shared = VoiceOverAnnouncer()

    /// The announcer drops identical messages in this window. This
    /// prevents speech floods from retry storms and event bursts.
    private static let dedupeWindow: TimeInterval = 3
    private var lastMessage: String?
    private var lastPostedAt: Date = .distantPast

    private init() {}

    func announce(_ message: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let now = Date()
        if message == lastMessage, now.timeIntervalSince(lastPostedAt) < Self.dedupeWindow {
            return
        }
        lastMessage = message
        lastPostedAt = now
        AccessibilityNotification.Announcement(message).post()
    }
}
