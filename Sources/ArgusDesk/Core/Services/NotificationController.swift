import Foundation
import UserNotifications

/// Sends macOS notifications when remote server severity changes.
///
/// The first completed remote refresh establishes a baseline and does not
/// notify. Later refreshes notify only on severity transitions, preventing
/// repeated alerts while a server remains in the same state.
@MainActor
final class NotificationController {
    /// Native macOS notification center when running inside an app bundle.
    ///
    /// `UNUserNotificationCenter.current()` raises an Objective-C exception for
    /// raw SwiftPM executables, so source-run builds must not initialize it.
    private let center: UNUserNotificationCenter?

    /// Last observed severity keyed by server name.
    private var previousSeverityByServer: [String: Severity] = [:]

    /// Whether status-change notifications are enabled.
    private var notificationsEnabled = false

    /// Whether recovery notifications are enabled.
    private var recoveryNotificationsEnabled = true

    /// Creates a controller that degrades gracefully outside an app bundle.
    init() {
        center = Bundle.main.bundleURL.pathExtension == "app"
            ? UNUserNotificationCenter.current()
            : nil
    }

    /// Applies notification preferences and requests authorization when needed.
    func configure(notificationsEnabled: Bool, recoveryNotificationsEnabled: Bool) {
        self.notificationsEnabled = notificationsEnabled
        self.recoveryNotificationsEnabled = recoveryNotificationsEnabled

        guard notificationsEnabled, let center else {
            return
        }

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("ArgusDesk notification warning: \(error.localizedDescription)")
            } else if !granted {
                print("ArgusDesk notification warning: permission was not granted.")
            }
        }
    }

    /// Evaluates a completed remote refresh and sends notifications for changes.
    func process(servers: [ServerStatus]) {
        var currentSeverityByServer: [String: Severity] = [:]
        for server in servers {
            currentSeverityByServer[server.name] = server.severity
        }

        guard !previousSeverityByServer.isEmpty else {
            previousSeverityByServer = currentSeverityByServer
            return
        }

        defer {
            previousSeverityByServer = currentSeverityByServer
        }

        guard notificationsEnabled else {
            return
        }

        for server in servers {
            guard
                let previousSeverity = previousSeverityByServer[server.name],
                previousSeverity != server.severity
            else {
                continue
            }

            if server.severity == .ok {
                guard recoveryNotificationsEnabled, previousSeverity == .warning || previousSeverity == .error else {
                    continue
                }

                send(
                    identifier: "\(server.name)-recovered",
                    title: "\(server.name) recovered",
                    body: server.headline
                )
                continue
            }

            guard server.severity == .warning || server.severity == .error else {
                continue
            }

            send(
                identifier: "\(server.name)-\(server.severity.rawValue)",
                title: "\(server.name): \(server.severity.rawValue)",
                body: problemSummary(for: server)
            )
        }
    }

    /// Sends one immediate macOS notification.
    private func send(identifier: String, title: String, body: String) {
        guard let center else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            if let error {
                print("ArgusDesk notification warning: \(error.localizedDescription)")
            }
        }
    }

    /// Summarizes the first few warning/error metrics for an alert body.
    private func problemSummary(for server: ServerStatus) -> String {
        let problems = server.metrics
            .filter { $0.severity == .warning || $0.severity == .error }
            .prefix(3)
            .map { "\($0.label) \($0.value)" }

        return problems.isEmpty ? server.headline : problems.joined(separator: ", ")
    }
}
