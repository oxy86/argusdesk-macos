import AppKit
import UserNotifications

/// Uses macOS banners, grouping, sounds, and the application's own icon.
/// Delivery remains subject to the user's Notifications and Focus settings.
@MainActor
final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter?
    private var tracker = MetricAlerts()
    private var enabled = false
    private var recovery = true
    var showDashboard: (() -> Void)?

    override init() {
        center = Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
        super.init()
        center?.delegate = self
    }

    func configure(notificationsEnabled: Bool, recoveryNotificationsEnabled: Bool) {
        if notificationsEnabled && !enabled { tracker = MetricAlerts() }
        enabled = notificationsEnabled
        recovery = recoveryNotificationsEnabled
        guard enabled else { return }
        center?.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { print("Notification authorization: \(error.localizedDescription)") }
        }
    }

    func process(servers: [ServerStatus], thresholds: Thresholds) {
        // Track changes while disabled; enabling alerts establishes a fresh tracker.
        let alerts = tracker.evaluate(servers: servers, thresholds: thresholds, recovery: recovery)
        guard enabled else { return }
        for alert in alerts { send(alert) }
    }

    /// A test must work independently of the saved monitoring toggle and must
    /// report denial/errors instead of silently submitting an undeliverable alert.
    func sendTest() async -> String {
        guard let center else { return "Notifications require the ArgusDesk.app bundle." }
        do {
            var settings = await permissionSnapshot(center)
            if settings.needsAuthorization {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                if !granted { return "Permission was not granted. Enable ArgusDesk in macOS Notification Settings." }
                settings = await permissionSnapshot(center)
            }
            guard settings.authorized else {
                return "Notifications are disabled for ArgusDesk. Enable Allow Notifications in macOS Notification Settings."
            }
            let content = UNMutableNotificationContent()
            content.title = "ArgusDesk — Test notification"
            content.body = "Native server alerts are ready. This is a test notification."
            content.sound = .default
            content.threadIdentifier = "ArgusDesk-test"
            let request = UNNotificationRequest(identifier: "test-" + UUID().uuidString,
                content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
            try await center.add(request)
            if !settings.bannersEnabled {
                return "Test scheduled, but banners are disabled. Choose Banners or Alerts in macOS Notification Settings."
            }
            return "Test scheduled for two seconds from now. If no banner appears, check Notification Center and Focus settings."
        } catch {
            return "Could not send the test notification: \(error.localizedDescription)"
        }
    }

    /// Older macOS SDKs do not mark UNNotificationSettings as Sendable.
    /// Read it inside the system callback and transfer only immutable booleans
    /// back to the main actor, rather than passing the SDK object across actors.
    private func permissionSnapshot(_ center: UNUserNotificationCenter) async -> NotificationPermissionSnapshot {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: NotificationPermissionSnapshot(
                    needsAuthorization: settings.authorizationStatus == .notDetermined,
                    authorized: settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
                    bannersEnabled: settings.alertSetting != .disabled && settings.alertStyle != .none
                ))
            }
        }
    }

    private func send(_ alert: MetricAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.threadIdentifier = alert.server
        content.sound = .default
        center?.add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil)) { error in
            if let error { print("Notification delivery: \(error.localizedDescription)") }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.showDashboard?() }
        completionHandler()
    }
}

/// Values safe to pass between the notification callback and the UI actor.
private struct NotificationPermissionSnapshot: Sendable {
    let needsAuthorization: Bool
    let authorized: Bool
    let bannersEnabled: Bool
}
