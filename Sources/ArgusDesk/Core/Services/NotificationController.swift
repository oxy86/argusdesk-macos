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
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                if !granted { return "Permission was not granted. Enable ArgusDesk in macOS Notification Settings." }
                settings = await center.notificationSettings()
            }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
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
            if settings.alertSetting == .disabled || settings.alertStyle == .none {
                return "Test scheduled, but banners are disabled. Choose Banners or Alerts in macOS Notification Settings."
            }
            return "Test scheduled for two seconds from now. If no banner appears, check Notification Center and Focus settings."
        } catch {
            return "Could not send the test notification: \(error.localizedDescription)"
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
