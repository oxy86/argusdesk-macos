import AppKit
import Combine

/// Application lifecycle bridge for the AppKit-based app shell.
///
/// The delegate owns the app controllers and coordinates configuration,
/// monitoring refreshes, preferences, window size, and notifications.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// Set by SwiftUI to recreate the dashboard after its last window closes.
    var openDashboard: (() -> Void)?
    private var backgroundActivity: NSObjectProtocol?
    private var configFilePath: String?
    private var localLabel: String?

    /// Strong reference to the preferences window controller.
    private var preferencesWindowController: PreferencesWindowController?

    /// Read-only server results shared with the menu, without local sample updates.
    let menuSnapshot = MenuSnapshot()

    /// Publishing the complete snapshot redraws the main dashboard.
    @Published var dashboardViewModel = DashboardViewModel.empty {
        didSet { menuSnapshot.update(from: dashboardViewModel) }
    }

    /// Local Mac monitor used by the refresh timer.
    private let localMonitor = LocalMonitor()

    /// Persists user-editable app behavior settings.
    private let preferencesStore = PreferencesStore()

    /// Sends remote server state-change notifications.
    private let notificationController = NotificationController()

    /// Repeating local stats timer.
    private var localRefreshTimer: Timer?

    /// Repeating remote server timer.
    private var remoteRefreshTimer: Timer?

    /// Local refresh interval from configuration.
    private var localRefreshSeconds = AppConfig.defaultLocalRefreshSeconds

    /// Remote refresh interval from configuration.
    private var remoteRefreshSeconds = AppConfig.defaultRemoteRefreshSeconds

    /// Main window width in points, persisted by preferences.
    private var mainWindowWidth: Int = 330

    /// Configurable severity thresholds from user preferences.
    private var thresholds = Thresholds.default

    /// Whether warning/error notifications are enabled.
    private var notificationsEnabled = false

    /// Whether recovery notifications are enabled.
    private var recoveryNotificationsEnabled = true

    /// Server configuration loaded at startup.
    private var serverConfigs: [ServerConfig] = []

    /// File path (or directory) used to load the configuration, for display.
    private var configSourceName = "not configured"

    /// Prevents overlapping remote refreshes if one run is still active.
    private var refreshSchedule = ServerRefreshSchedule()
    private var configGeneration = 0

    /// Loads configuration and starts monitoring before the first window appears.
    /// SwiftUI owns the single menu bar item for the lifetime of the app.
    override init() {
        super.init()

        // Load user preferences first so we can honour a stored config path.
        let preferences = preferencesStore.load(
            fallback: AppPreferences(
                localRefreshSeconds: AppConfig.defaultLocalRefreshSeconds,
                remoteRefreshSeconds: AppConfig.defaultRemoteRefreshSeconds,
                overlayWidth: 330,
                configFilePath: nil,
                notificationsEnabled: false,
                recoveryNotificationsEnabled: true,
                thresholds: .default
            )
        )

        configFilePath = preferences.configFilePath

        // Load configuration (respecting a stored config path).
        do {
            var configLoader = ConfigLoader()
            let loadedConfig = try configLoader.load(from: preferences.configFilePath)
            let viewModel = DashboardViewModel.pending(
                config: loadedConfig.config,
                configSource: loadedConfig.sourceURL,
                validation: loadedConfig.validation
            )
            dashboardViewModel = viewModel
            serverConfigs = loadedConfig.config.servers
            localLabel = loadedConfig.config.localLabel
            configSourceName = loadedConfig.sourceURL.lastPathComponent
            configFilePath = loadedConfig.sourceURL.path
            UserDefaults.standard.set(configFilePath, forKey: "configFilePath")
        } catch {
            let fallbackConfig = AppConfig()
            dashboardViewModel = DashboardViewModel.pending(
                config: fallbackConfig,
                configSource: URL(fileURLWithPath: "no config file found"),
                validation: nil
            )
            configSourceName = "no config file found"
        }

        localRefreshSeconds = preferences.localRefreshSeconds
        remoteRefreshSeconds = preferences.remoteRefreshSeconds
        dashboardViewModel = dashboardViewModel.updating(remoteRefreshSeconds: remoteRefreshSeconds)
        mainWindowWidth = preferences.overlayWidth
        thresholds = preferences.thresholds
        notificationsEnabled = preferences.notificationsEnabled
        recoveryNotificationsEnabled = preferences.recoveryNotificationsEnabled
        notificationController.configure(
            notificationsEnabled: notificationsEnabled,
            recoveryNotificationsEnabled: recoveryNotificationsEnabled
        )

        notificationController.showDashboard = { [weak self] in self?.showDashboard() }
        // App Nap must not suspend the timer simply because every window is hidden.
        // This activity does not prevent normal system sleep.
        backgroundActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .automaticTerminationDisabled], reason: "Monitoring server thresholds")
        refreshLocalStatus()
        startLocalRefreshTimer()
        startRemoteRefreshTimer()

        let severityEngine = SeverityEngine(thresholds: preferences.thresholds)
        refreshRemoteStatus(severityEngine: severityEngine)
    }

    /// Closing a window leaves the monitoring owner and menu bar alive.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: "startHidden") { NSApp.hide(nil) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        // showDashboard handles reopening. Returning false prevents AppKit
        // from also performing its default window-reopen action.
        return false
    }

    func showDashboard() {
        openDashboard?()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Captures fresh local status and updates the dashboard.
    private func refreshLocalStatus() {
        dashboardViewModel = dashboardViewModel.updating(local: localMonitor.snapshot(label: localLabel))
    }

    /// Starts the local refresh timer.
    private func startLocalRefreshTimer() {
        localRefreshTimer?.invalidate()

        let interval = TimeInterval(max(1, localRefreshSeconds))
        localRefreshTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLocalStatus()
            }
        }
        if let localRefreshTimer { RunLoop.main.add(localRefreshTimer, forMode: .common) }
    }

    /// Starts the remote server refresh loop.
    private func startRemoteRefreshTimer() {
        remoteRefreshTimer?.invalidate()

        let interval: TimeInterval = 1
        remoteRefreshTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRemoteStatus(severityEngine: SeverityEngine(thresholds: self?.thresholds ?? .default), force: false)
            }
        }
        if let remoteRefreshTimer { RunLoop.main.add(remoteRefreshTimer, forMode: .common) }
    }

    /// Starts only due connections. Each task publishes its own result instead
    /// of making fast cards wait for the slowest server in a batch.
    private func refreshRemoteStatus(severityEngine: SeverityEngine, force: Bool = true) {
        let now = ProcessInfo.processInfo.systemUptime
        let generation = configGeneration
        for server in serverConfigs {
            guard refreshSchedule.begin(server, now: now, global: remoteRefreshSeconds, force: force) else { continue }
            let monitor = RemoteMonitor(servers: [server], severityEngine: severityEngine)
            Task {
                let statuses = await monitor.refreshAll()
                self.refreshSchedule.finish(server, now: ProcessInfo.processInfo.systemUptime)
                guard generation == self.configGeneration,
                      let index = self.serverConfigs.firstIndex(where: { $0.connectionID == server.connectionID }),
                      self.dashboardViewModel.servers.indices.contains(index), var status = statuses.first else {
                    return
                }
                // Re-evaluate using current settings if thresholds changed while
                // the network request was running.
                let metrics = SeverityEngine(thresholds: self.thresholds).evaluate(metrics: status.metrics)
                status = ServerStatus(name: status.name,
                    severity: SeverityEngine(thresholds: self.thresholds).serverSeverity(for: metrics),
                    headline: status.headline, metrics: metrics,
                    refreshInterval: "\(server.effectiveRefreshSeconds(global: self.remoteRefreshSeconds))s",
                    lastResultAt: Date())
                var servers = self.dashboardViewModel.servers
                servers[index] = status
                self.dashboardViewModel = self.dashboardViewModel.updating(servers: servers,
                    lastRefresh: Self.refreshTimeFormatter.string(from: Date()))
                self.notificationController.process(servers: servers, thresholds: self.thresholds)
            }
        }
    }

    /// Menu commands share the dashboard's monitoring owner and current thresholds.
    func refreshNow() {
        refreshRemoteStatus(severityEngine: SeverityEngine(thresholds: thresholds))
    }

    /// Opens the Preferences window, creating it on first use.

    /// Public method called from SwiftUI menu bar extra.
    func showPreferencesAction() {
        showPreferences()
    }
    private func showPreferences() {
        if let preferencesWindowController, preferencesWindowController.window?.isVisible == true {
            preferencesWindowController.show()
            return
        }

        let preferences = AppPreferences(
            localRefreshSeconds: localRefreshSeconds,
            remoteRefreshSeconds: remoteRefreshSeconds,
            overlayWidth: mainWindowWidth,
            configFilePath: configFilePath,
            notificationsEnabled: notificationsEnabled,
            recoveryNotificationsEnabled: recoveryNotificationsEnabled,
            thresholds: thresholds
        )

        let controller = PreferencesWindowController(
            preferences: preferences,
            configSourceName: configSourceName,
            serverCount: serverConfigs.count,
            servers: serverConfigs,
            localLabel: localLabel,
            saveRefreshIntervals: { [weak self] values, label in
                guard let path = self?.configFilePath else { return "Select a configuration file first." }
                return ConfigSaver.saveRefreshIntervals(to: URL(fileURLWithPath: path), values: values, localLabel: label)
            },
            apply: { [weak self] preferences in
                self?.apply(preferences: preferences)
            },
            testNotification: { [weak self] in
                guard let self else { return "ArgusDesk is no longer running." }
                return await self.notificationController.sendTest()
            }
        )
        preferencesWindowController = controller
        controller.show()
    }

    /// Persists preference changes and immediately restarts refresh timers.
    private func apply(preferences: AppPreferences) {
        preferencesStore.save(preferences)
        configFilePath = preferences.configFilePath
        localRefreshSeconds = preferences.localRefreshSeconds
        remoteRefreshSeconds = preferences.remoteRefreshSeconds
        mainWindowWidth = preferences.overlayWidth
        thresholds = preferences.thresholds
        notificationsEnabled = preferences.notificationsEnabled
        recoveryNotificationsEnabled = preferences.recoveryNotificationsEnabled
        notificationController.configure(
            notificationsEnabled: notificationsEnabled,
            recoveryNotificationsEnabled: recoveryNotificationsEnabled
        )
        dashboardViewModel = dashboardViewModel.updating(remoteRefreshSeconds: remoteRefreshSeconds)
        startLocalRefreshTimer()
        refreshSchedule.resetDeadlines()
        startRemoteRefreshTimer()

        // Reload configuration if the user changed the config path.
        if preferences.configFilePath != nil {
            reloadConfiguration(from: preferences.configFilePath)
            refreshLocalStatus()
            refreshRemoteStatus(severityEngine: SeverityEngine(thresholds: thresholds))
        }
    }

    /// Reloads the configuration from the given path (or default search).
    private func reloadConfiguration(from path: String?) {
        do {
            var configLoader = ConfigLoader()
            let loadedConfig = try configLoader.load(from: path)
            configGeneration += 1
            refreshSchedule.resetDeadlines()
            serverConfigs = loadedConfig.config.servers
            localLabel = loadedConfig.config.localLabel
            configSourceName = loadedConfig.sourceURL.lastPathComponent

            dashboardViewModel = dashboardViewModel.replacing(
                config: loadedConfig.config,
                servers: loadedConfig.config.servers,
                validation: loadedConfig.validation
            )
        } catch {
            // If reloading fails, keep existing state.
            configSourceName = "config reload failed"
            dashboardViewModel = dashboardViewModel.replacing(
                config: AppConfig(),
                servers: [],
                validation: nil
            )
        }
    }
}

private extension AppDelegate {
    /// Shared formatter for compact refresh timestamps in the window header.
    static let refreshTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
