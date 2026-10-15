import AppKit
import SwiftUI
import ServiceManagement

/// Owns the native ArgusDesk Preferences window.
///
/// The window edits app behavior settings including refresh intervals,
/// window size, notification toggles, severity thresholds, and the JSON
/// configuration file path. Remote server definitions remain in that
/// JSON file; this app only reads it.
@MainActor
final class PreferencesWindowController: NSWindowController {
    /// Creates the preferences window with the current settings.
    init(
        preferences: AppPreferences,
        configSourceName: String,
        serverCount: Int,
        servers: [ServerConfig],
        localLabel: String?,
        saveRefreshIntervals: @escaping ([String: String], String) -> String?,
        apply: @escaping (AppPreferences) -> Void,
        testNotification: @escaping () async -> String
    ) {
        let rootView = PreferencesView(
            initialPreferences: preferences,
            configSourceName: configSourceName,
            serverCount: serverCount,
            servers: servers,
            localLabel: localLabel,
            saveRefreshIntervals: saveRefreshIntervals,
            apply: apply,
            testNotification: testNotification
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "ArgusDesk Preferences"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 460, height: 540))
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
    @AppStorage("startHidden") private var startHidden = false
    @State private var launchAtLogin = LoginItemController().enabled
    @State private var loginMessage = ""

    /// Layout changes are saved and applied immediately to the dashboard.
    @AppStorage("serverLayout") private var serverLayout: ServerLayout = .vertical
    /// Closes the preferences window.
    @Environment(\.dismiss) private var dismiss

    /// Editable local refresh interval.
    @State private var localRefreshSeconds: Int

    /// Editable remote refresh interval.
    @State private var remoteRefreshSeconds: Int

    /// Editable window width.
    @State private var overlayWidth: Int

    /// User-selected config file path, or nil to use the default search.
    @State private var configFilePath: String?

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

    @State private var gpuWarningPercent: Double
    @State private var gpuErrorPercent: Double
    @State private var gpuMemoryWarningPercent: Double
    @State private var gpuMemoryErrorPercent: Double
    @State private var serverRefreshText: [String: String]
    @State private var saveFeedback = ""
    private let originalConfigPath: String?
    let servers: [ServerConfig]
    let saveRefreshIntervals: ([String: String], String) -> String?
    @State private var localLabelText: String

    private var invalidRefresh: Bool {
        serverRefreshText.values.contains {
            let text = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && (Int(text) ?? 0) <= 0
        }
    }

    /// Dedicated PHP-FPM CPU thresholds, independent of other services.
    @State private var phpFPMCPUWarningPercent: Double
    @State private var phpFPMCPUErrorPercent: Double

    /// Name of the JSON configuration source.
    let configSourceName: String

    /// Number of configured remote servers.
    let serverCount: Int

    /// Called when the user applies changes.
    let apply: (AppPreferences) -> Void
    let testNotification: () async -> String
    @State private var notificationFeedback = ""
    @State private var isTestingNotification = false

    /// Creates the view with current preference values.
    init(
        initialPreferences: AppPreferences,
        configSourceName: String,
        serverCount: Int,
        servers: [ServerConfig],
        localLabel: String?,
        saveRefreshIntervals: @escaping ([String: String], String) -> String?,
        apply: @escaping (AppPreferences) -> Void,
        testNotification: @escaping () async -> String
    ) {
        _localLabelText = State(initialValue: localLabel ?? "")
        self.servers = servers
        self.saveRefreshIntervals = saveRefreshIntervals
        self.originalConfigPath = initialPreferences.configFilePath
        _serverRefreshText = State(initialValue: Dictionary(servers.map { ($0.connectionID, $0.refreshSeconds.map(String.init) ?? "") }, uniquingKeysWith: { first, _ in first }))
        _gpuWarningPercent = State(initialValue: initialPreferences.thresholds.gpuWarningPercent)
        _gpuErrorPercent = State(initialValue: initialPreferences.thresholds.gpuErrorPercent)
        _gpuMemoryWarningPercent = State(initialValue: initialPreferences.thresholds.gpuMemoryWarningPercent)
        _gpuMemoryErrorPercent = State(initialValue: initialPreferences.thresholds.gpuMemoryErrorPercent)
        _localRefreshSeconds = State(initialValue: initialPreferences.localRefreshSeconds)
        _remoteRefreshSeconds = State(initialValue: initialPreferences.remoteRefreshSeconds)
        _overlayWidth = State(initialValue: initialPreferences.overlayWidth)
        _configFilePath = State(initialValue: initialPreferences.configFilePath)
        _notificationsEnabled = State(initialValue: initialPreferences.notificationsEnabled)
        _recoveryNotificationsEnabled = State(initialValue: initialPreferences.recoveryNotificationsEnabled)
        _pingWarningMilliseconds = State(initialValue: initialPreferences.thresholds.pingWarningMilliseconds)
        _pingErrorMilliseconds = State(initialValue: initialPreferences.thresholds.pingErrorMilliseconds)
        _usageWarningPercent = State(initialValue: initialPreferences.thresholds.usageWarningPercent)
        _usageErrorPercent = State(initialValue: initialPreferences.thresholds.usageErrorPercent)
        _serviceCPUWarningPercent = State(initialValue: initialPreferences.thresholds.serviceCPUWarningPercent)
        _serviceCPUErrorPercent = State(initialValue: initialPreferences.thresholds.serviceCPUErrorPercent)
        _phpFPMCPUWarningPercent = State(initialValue: initialPreferences.thresholds.phpFPMCPUWarningPercent)
        _phpFPMCPUErrorPercent = State(initialValue: initialPreferences.thresholds.phpFPMCPUErrorPercent)
        self.configSourceName = configSourceName
        self.serverCount = serverCount
        self.apply = apply
        self.testNotification = testNotification
    }

    /// Presents a file picker so the user can select a JSON config file.
    private func pickConfigFile() {
        let panel = NSOpenPanel()
        panel.title = "Select configuration file"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            configFilePath = url.path
        }
    }

    /// Shows a folder picker so the user can select a directory.
    ///
    /// The app then looks for `servers.json` inside that directory.
    private func pickConfigDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Select configuration directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            // Store the directory URL; ConfigLoader will look for servers.json inside it.
            configFilePath = url.path
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("ArgusDesk")
                    .font(.title2.weight(.semibold))

                // --- Configuration ---
                SectionLabel(title: "Configuration")
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                    GridRow {
                        Text("Config file")
                        HStack(spacing: 4) {
                            Text(configFilePath != nil
                                ? configFilePath!
                                : "Default search")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Button(action: pickConfigFile) {
                                Image(systemName: "folder.badge.gearpath")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Choose a specific config file")
                        }
                    }
                    GridRow {
                        Text("Servers")
                        Text("\(serverCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.bottom, 8)

                // --- Refresh and display ---
                SectionLabel(title: "Display & Refresh")
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                    GridRow {
                        Text("Local refresh")
                        Stepper("\(localRefreshSeconds)s", value: $localRefreshSeconds, in: 1...300)
                    }
                    GridRow {
                        Text("Remote refresh")
                        Stepper("\(remoteRefreshSeconds)s", value: $remoteRefreshSeconds, in: 1...600)
                    }
                    GridRow {
                        Text("Server layout")
                        Picker("Server layout", selection: $serverLayout) {
                            ForEach(ServerLayout.allCases) { layout in
                                Text(layout.title).tag(layout)
                            }
                        }
                        .labelsHidden()
                    }
                }
                .padding(.bottom, 8)

                Divider()

                SectionLabel(title: "Startup")
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { requested in
                    do {
                        try LoginItemController().setEnabled(requested)
                        loginMessage = LoginItemController().needsApproval ? "Approve ArgusDesk in System Settings → General → Login Items." : ""
                    } catch { loginMessage = error.localizedDescription }
                    launchAtLogin = LoginItemController().enabled
                }))
                .disabled(Bundle.main.bundleURL.pathExtension != "app")
                Toggle("Start with dashboard hidden", isOn: $startHidden)
                Text("Monitoring continues when the window is closed or hidden. Quit stops monitoring.")
                    .font(.caption).foregroundStyle(.secondary)
                if !loginMessage.isEmpty { Text(loginMessage).font(.caption).foregroundStyle(.secondary) }
                Button("Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }

                HStack {
                    Text("Local label")
                    TextField("Mac hostname", text: $localLabelText)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Leave the local label blank to use the Mac hostname.")
                    .font(.caption).foregroundStyle(.secondary)
                SectionLabel(title: "Per-server refresh (seconds)")
                Text("Leave a field empty to use the global remote refresh. Saved to your local configuration file when you Apply.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(servers.indices, id: \.self) { index in
                    let server = servers[index]
                    HStack {
                        Text(server.displayName).lineLimit(1)
                        Spacer()
                        TextField("Global: \(remoteRefreshSeconds)s", text: Binding(
                            get: { serverRefreshText[server.connectionID] ?? "" },
                            set: { serverRefreshText[server.connectionID] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder).frame(width: 110)
                    }
                }
                if invalidRefresh {
                    Text("Refresh intervals must be empty or positive whole seconds.")
                        .font(.caption).foregroundStyle(.red)
                }
                if !saveFeedback.isEmpty { Text(saveFeedback).font(.caption).foregroundStyle(.red) }

                // --- Notifications ---
                SectionLabel(title: "Notifications")
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Warning and error alerts", isOn: $notificationsEnabled)
                    Button("Send test notification") {
                        isTestingNotification = true
                        notificationFeedback = "Checking macOS notification permission…"
                        Task {
                            notificationFeedback = await testNotification()
                            isTestingNotification = false
                        }
                    }
                    .disabled(isTestingNotification)
                    if !notificationFeedback.isEmpty {
                        Text(notificationFeedback).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("macOS Notification Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Text("The test requests permission itself. For ongoing alerts, enable warning/error alerts and click Apply. Focus and system settings control banner delivery.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Recovery alerts", isOn: $recoveryNotificationsEnabled)
                        .disabled(!notificationsEnabled)
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
                    title: "Other Services CPU (%)",
                    warning: $serviceCPUWarningPercent,
                    error: $serviceCPUErrorPercent,
                    warnRange: 1...50,
                    errRange: 5...80
                )
                .padding(.bottom, 8)

                thresholdSection(
                    title: "PHP-FPM CPU (%)",
                    warning: $phpFPMCPUWarningPercent,
                    error: $phpFPMCPUErrorPercent,
                    warnRange: 1...99,
                    errRange: 2...100
                )
                Text("Service rows show state, RAM, then CPU. CPU is normalized to the server's total logical CPU capacity.")
                    .font(.caption).foregroundStyle(.secondary)

                thresholdSection(title: "GPU Utilization (%)", warning: $gpuWarningPercent,
                    error: $gpuErrorPercent, warnRange: 1...99, errRange: 2...100)
                thresholdSection(title: "GPU Memory / VRAM (%)", warning: $gpuMemoryWarningPercent,
                    error: $gpuMemoryErrorPercent, warnRange: 1...99, errRange: 2...100)
                Text("High GPU utilization is expected while generating with local models; tune these limits to your workload.")
                    .font(.caption).foregroundStyle(.secondary)

                if phpFPMCPUWarningPercent >= phpFPMCPUErrorPercent || serviceCPUWarningPercent >= serviceCPUErrorPercent
                    || usageWarningPercent >= usageErrorPercent || pingWarningMilliseconds >= pingErrorMilliseconds
                    || gpuWarningPercent >= gpuErrorPercent || gpuMemoryWarningPercent >= gpuMemoryErrorPercent {
                    Text("Each warning threshold must be lower than its critical threshold.")
                        .font(.caption).foregroundStyle(.red)
                }

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
                        saveFeedback = ""
                        if configFilePath == originalConfigPath, let error = saveRefreshIntervals(serverRefreshText, localLabelText) {
                            saveFeedback = error
                            return
                        }
                        apply(
                            AppPreferences(
                                localRefreshSeconds: localRefreshSeconds,
                                remoteRefreshSeconds: remoteRefreshSeconds,
                                overlayWidth: overlayWidth,
                                configFilePath: configFilePath,
                                notificationsEnabled: notificationsEnabled,
                                recoveryNotificationsEnabled: recoveryNotificationsEnabled,
                                thresholds: Thresholds(
                                    pingWarningMilliseconds: pingWarningMilliseconds,
                                    pingErrorMilliseconds: pingErrorMilliseconds,
                                    usageWarningPercent: usageWarningPercent,
                                    usageErrorPercent: usageErrorPercent,
                                    serviceCPUWarningPercent: serviceCPUWarningPercent,
                                    serviceCPUErrorPercent: serviceCPUErrorPercent,
                                    phpFPMCPUWarningPercent: phpFPMCPUWarningPercent,
                                    phpFPMCPUErrorPercent: phpFPMCPUErrorPercent,
                                    gpuWarningPercent: gpuWarningPercent,
                                    gpuErrorPercent: gpuErrorPercent,
                                    gpuMemoryWarningPercent: gpuMemoryWarningPercent,
                                    gpuMemoryErrorPercent: gpuMemoryErrorPercent
                                )
                            )
                        )
                    }
                    .disabled(phpFPMCPUWarningPercent >= phpFPMCPUErrorPercent
                        || serviceCPUWarningPercent >= serviceCPUErrorPercent
                        || usageWarningPercent >= usageErrorPercent
                        || pingWarningMilliseconds >= pingErrorMilliseconds || invalidRefresh
                        || gpuWarningPercent >= gpuErrorPercent || gpuMemoryWarningPercent >= gpuMemoryErrorPercent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
        .frame(width: 460, height: 540)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin = LoginItemController().enabled
            if LoginItemController().needsApproval {
                loginMessage = "Approve ArgusDesk in System Settings → General → Login Items."
            }
        }
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
