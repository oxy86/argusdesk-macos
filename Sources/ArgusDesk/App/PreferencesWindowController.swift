import AppKit
import SwiftUI

/// Owns the native ArgusDesk Preferences window.
///
/// The window edits app behavior settings including refresh intervals,
/// overlay size, notification toggles, and severity thresholds. Remote
/// server definitions remain in the local JSON configuration file.
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
        window.setContentSize(NSSize(width: 460, height: 520))
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

    /// Editable overlay window width.
    @State private var overlayWidth: Int

    /// Whether status-change notifications are enabled.
    @State private var notificationsEnabled: Bool

    /// Whether recovery notifications are enabled.
    @State private var recoveryNotificationsEnabled: Bool

    /// Ping warning threshold (ms).
    @State private var pingWarningMilliseconds: Double

    /// Ping error threshold (ms).
    @State private var pingErrorMilliseconds: Double

    /// Usage (disk/memory) warning threshold (%).
    @State private var usageWarningPercent: Double

    /// Usage (disk/memory) error threshold (%).
    @State private var usageErrorPercent: Double

    /// Service CPU warning threshold (%).
    @State private var serviceCPUWarningPercent: Double

    /// Service CPU error threshold (%).
    @State private var serviceCPUErrorPercent: Double

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
        _overlayWidth = State(initialValue: initialPreferences.overlayWidth)
        _notificationsEnabled = State(initialValue: initialPreferences.notificationsEnabled)
        _recoveryNotificationsEnabled = State(initialValue: initialPreferences.recoveryNotificationsEnabled)
        _pingWarningMilliseconds = State(initialValue: initialPreferences.thresholds.pingWarningMilliseconds)
        _pingErrorMilliseconds = State(initialValue: initialPreferences.thresholds.pingErrorMilliseconds)
        _usageWarningPercent = State(initialValue: initialPreferences.thresholds.usageWarningPercent)
        _usageErrorPercent = State(initialValue: initialPreferences.thresholds.usageErrorPercent)
        _serviceCPUWarningPercent = State(initialValue: initialPreferences.thresholds.serviceCPUWarningPercent)
        _serviceCPUErrorPercent = State(initialValue: initialPreferences.thresholds.serviceCPUErrorPercent)
        self.configSourceName = configSourceName
        self.serverCount = serverCount
        self.apply = apply
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("ArgusDesk")
                    .font(.title2.weight(.semibold))

                // --- Refresh and display ---
                SectionLabel(title: "Display & Refresh")
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                    GridRow {
                        Text("Local refresh")
                        Stepper("\(localRefreshSeconds) seconds", value: $localRefreshSeconds, in: 1...300)
                    }
                    GridRow {
                        Text("Remote refresh")
                        Stepper("\(remoteRefreshSeconds) seconds", value: $remoteRefreshSeconds, in: 5...3_600, step: 5)
                    }
                    GridRow {
                        Text("Overlay width")
                        Stepper("\(overlayWidth) points", value: $overlayWidth, in: 260...600)
                    }
                }
                .padding(.bottom, 8)

                Divider()

                // --- Notifications ---
                SectionLabel(title: "Notifications")
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                    GridRow {
                        Text("Status changes")
                        Toggle("", isOn: $notificationsEnabled)
                    }
                    GridRow {
                        Text("Recovery alerts")
                        Toggle("", isOn: $recoveryNotificationsEnabled)
                            .disabled(!notificationsEnabled)
                    }
                }
                .padding(.bottom, 8)

                Divider()

                // --- Thresholds ---
                SectionLabel(title: "Severity Thresholds")

                thresholdSection(
                    title: "Ping Latency (ms)",
                    warning: $pingWarningMilliseconds,
                    error: $pingErrorMilliseconds,
                    warnRange: 10...1000,
                    errRange: 100...10000
                )
                .padding(.bottom, 8)

                thresholdSection(
                    title: "Disk / Memory Usage (%)",
                    warning: $usageWarningPercent,
                    error: $usageErrorPercent,
                    warnRange: 50...95,
                    errRange: 60...99
                )
                .padding(.bottom, 8)

                thresholdSection(
                    title: "Service CPU (%)",
                    warning: $serviceCPUWarningPercent,
                    error: $serviceCPUErrorPercent,
                    warnRange: 1...50,
                    errRange: 5...80
                )
                .padding(.bottom, 8)

                Divider()

                // --- Config info (read-only) ---
                SectionLabel(title: "Configuration")
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                    GridRow {
                        Text("Config file")
                        Text(configSourceName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    GridRow {
                        Text("Servers")
                        Text("\(serverCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.bottom, 8)

                // --- Buttons ---
                HStack {
                    Text(AppVersion.displayName)
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    Spacer()

                    Button("Close") {
                        dismiss()
                    }

                    Button("Apply") {
                        apply(
                            AppPreferences(
                                localRefreshSeconds: localRefreshSeconds,
                                remoteRefreshSeconds: remoteRefreshSeconds,
                                overlayWidth: overlayWidth,
                                notificationsEnabled: notificationsEnabled,
                                recoveryNotificationsEnabled: recoveryNotificationsEnabled,
                                thresholds: Thresholds(
                                    pingWarningMilliseconds: pingWarningMilliseconds,
                                    pingErrorMilliseconds: pingErrorMilliseconds,
                                    usageWarningPercent: usageWarningPercent,
                                    usageErrorPercent: usageErrorPercent,
                                    serviceCPUWarningPercent: serviceCPUWarningPercent,
                                    serviceCPUErrorPercent: serviceCPUErrorPercent
                                )
                            )
                        )
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
        .frame(width: 460, height: 520)
    }
}

/// A reusable section for a single threshold pair (warning / error).
private struct thresholdSection: View {
    let title: String
    @Binding var warning: Double
    @Binding var error: Double
    let warnRange: ClosedRange<Double>
    let errRange: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Warning:")
                        .font(.caption)
                        .frame(width: 60, alignment: .trailing)
                    Stepper("\(Int(warning))", value: $warning, in: warnRange)
                }

                HStack(spacing: 6) {
                    Text("Error:")
                        .font(.caption)
                        .frame(width: 60, alignment: .trailing)
                    Stepper("\(Int(error))", value: $error, in: errRange)
                }
            }
        }
    }
}

/// Simple section label.
private struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}
