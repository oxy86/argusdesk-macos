import AppKit
import SwiftUI

/// Owns the native ArgusDesk Preferences window.
///
/// The window edits app behavior settings only. Remote server definitions and
/// credentials remain in the local JSON configuration file.
@MainActor
final class PreferencesWindowController: NSWindowController {
    /// Creates the preferences window with the current settings.
    init(
        preferences: AppPreferences,
        configSourceName: String,
        serverCount: Int,
        apply: @escaping (AppPreferences) -> Void
    ) {
        let rootView = PreferencesView(
            initialPreferences: preferences,
            configSourceName: configSourceName,
            serverCount: serverCount,
            apply: apply
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "ArgusDesk Preferences"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 430, height: 330))
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    /// Storyboards are not used by the SwiftPM app shell.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    /// Brings the preferences window forward.
    func show() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// SwiftUI contents of the Preferences window.
private struct PreferencesView: View {
    /// Closes the preferences window.
    @Environment(\.dismiss) private var dismiss

    /// Editable local refresh interval.
    @State private var localRefreshSeconds: Int

    /// Editable remote refresh interval.
    @State private var remoteRefreshSeconds: Int

    /// Whether status-change notifications are enabled.
    @State private var notificationsEnabled: Bool

    /// Whether recovery notifications are enabled.
    @State private var recoveryNotificationsEnabled: Bool

    /// Name of the JSON configuration source.
    let configSourceName: String

    /// Number of configured remote servers.
    let serverCount: Int

    /// Called when the user applies changes.
    let apply: (AppPreferences) -> Void

    /// Creates the view with current preference values.
    init(
        initialPreferences: AppPreferences,
        configSourceName: String,
        serverCount: Int,
        apply: @escaping (AppPreferences) -> Void
    ) {
        _localRefreshSeconds = State(initialValue: initialPreferences.localRefreshSeconds)
        _remoteRefreshSeconds = State(initialValue: initialPreferences.remoteRefreshSeconds)
        _notificationsEnabled = State(initialValue: initialPreferences.notificationsEnabled)
        _recoveryNotificationsEnabled = State(initialValue: initialPreferences.recoveryNotificationsEnabled)
        self.configSourceName = configSourceName
        self.serverCount = serverCount
        self.apply = apply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ArgusDesk")
                .font(.title2.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    Text("Local refresh")
                    Stepper(value: $localRefreshSeconds, in: 1...300) {
                        Text("\(localRefreshSeconds) seconds")
                            .frame(width: 110, alignment: .trailing)
                    }
                }

                GridRow {
                    Text("Remote refresh")
                    Stepper(value: $remoteRefreshSeconds, in: 5...3_600, step: 5) {
                        Text("\(remoteRefreshSeconds) seconds")
                            .frame(width: 110, alignment: .trailing)
                    }
                }

                GridRow {
                    Text("Notifications")
                    Toggle("Status changes", isOn: $notificationsEnabled)
                }

                GridRow {
                    Text("Recovery alerts")
                    Toggle("Server recovered", isOn: $recoveryNotificationsEnabled)
                        .disabled(!notificationsEnabled)
                }

                GridRow {
                    Text("Configuration")
                    Text(configSourceName)
                        .foregroundStyle(.secondary)
                }

                GridRow {
                    Text("Servers")
                    Text("\(serverCount)")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                Text(AppVersion.displayName)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Close") {
                    dismiss()
                }

                Button("Apply") {
                    apply(
                        AppPreferences(
                            localRefreshSeconds: localRefreshSeconds,
                            remoteRefreshSeconds: remoteRefreshSeconds,
                            notificationsEnabled: notificationsEnabled,
                            recoveryNotificationsEnabled: recoveryNotificationsEnabled
                        )
                    )
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 430, height: 330)
    }
}
