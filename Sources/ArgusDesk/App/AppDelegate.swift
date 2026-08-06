import AppKit

/// Application lifecycle bridge for the AppKit-based app shell.
///
/// The delegate owns the app controllers and coordinates configuration,
/// monitoring refreshes, preferences, overlay size, and notifications.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Strong reference to the overlay controller.
    ///
    /// AppKit windows/controllers are not retained automatically in this setup,
    /// so the app delegate keeps the controller alive.
    private var overlayWindowController: OverlayWindowController?

    /// Strong reference to the menu bar controller.
    private var menuBarController: MenuBarController?

    /// Strong reference to the preferences window controller.
    private var preferencesWindowController: PreferencesWindowController?

    /// Latest dashboard snapshot shown in the overlay.
    private var dashboardViewModel = DashboardViewModel.empty

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

    /// Overlay width in points, persisted by preferences.
    private var overlayWidth: Int = 330

    /// Configurable severity thresholds from user preferences.
    private var thresholds = Thresholds.default

    /// Whether warning/error notifications are enabled.
    private var notificationsEnabled = false

    /// Whether recovery notifications are enabled.
    private var recoveryNotificationsEnabled = true

    /// Server configuration loaded at startup.
    private var serverConfigs: [ServerConfig] = []

    /// Name of the configuration file loaded at startup.
    private var configSourceName = "not configured"

    /// Prevents overlapping remote refreshes if one run is still active.
    private var isRemoteRefreshRunning = false

    /// Creates the overlay as soon as the app finishes launching.
    ///
    /// The app loads JSON configuration before creating the window. If loading
    /// fails, it falls back to an empty dashboard and logs a readable error
    /// instead of blocking launch. Local and remote refresh timers then update
    /// their sections independently.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let initialDashboard = loadInitialDashboard()
        let preferences = preferencesStore.load(
            fallback: AppPreferences(
                localRefreshSeconds: initialDashboard.localRefreshSeconds,
                remoteRefreshSeconds: initialDashboard.remoteRefreshSeconds,
                overlayWidth: 330,
                notificationsEnabled: false,
                recoveryNotificationsEnabled: true,
                thresholds: .default
            )
        )
        localRefreshSeconds = preferences.localRefreshSeconds
        remoteRefreshSeconds = preferences.remoteRefreshSeconds
        overlayWidth = preferences.overlayWidth
        thresholds = preferences.thresholds
        notificationsEnabled = preferences.notificationsEnabled
        recoveryNotificationsEnabled = preferences.recoveryNotificationsEnabled
        notificationController.configure(
            notificationsEnabled: notificationsEnabled,
            recoveryNotificationsEnabled: recoveryNotificationsEnabled
        )
        serverConfigs = initialDashboard.servers
        configSourceName = initialDashboard.configSourceName
        dashboardViewModel = initialDashboard.viewModel
            .updating(local: localMonitor.snapshot())
            .updating(remoteRefreshSeconds: remoteRefreshSeconds)

        let severityEngine = SeverityEngine(thresholds: preferences.thresholds)
        let overlayController = OverlayWindowController(
            viewModel: dashboardViewModel,
            overlayWidth: overlayWidth
        ) { [weak self] in
            self?.showPreferences()
        }
        overlayWindowController = overlayController
        overlayController.show()

        let menuController = MenuBarController(
            dashboard: dashboardViewModel,
            refreshNow: { [weak self] in
                self?.refreshRemoteStatus(severityEngine: severityEngine)
            },
            showOverlay: { [weak self] in
                self?.overlayWindowController?.show()
            },
            showPreferences: { [weak self] in
                self?.showPreferences()
            },
            quit: {
                NSApp.terminate(nil)
            }
        )
        menuBarController = menuController

        startLocalRefreshTimer()
        startRemoteRefreshTimer()
        refreshRemoteStatus(severityEngine: severityEngine)
    }

    /// Loads configuration and converts it into the initial dashboard.
    private func loadInitialDashboard() -> InitialDashboard {
        do {
            var configLoader = ConfigLoader()
            let loadedConfig = try configLoader.load()
            let viewModel = DashboardViewModel.pending(
                config: loadedConfig.config,
                configSource: loadedConfig.sourceURL,
                validation: loadedConfig.validation
            )
            return InitialDashboard(
                viewModel: viewModel,
                localRefreshSeconds: loadedConfig.config.localRefreshSeconds,
                remoteRefreshSeconds: loadedConfig.config.remoteRefreshSeconds,
                servers: loadedConfig.config.servers,
                configSourceName: loadedConfig.sourceURL.lastPathComponent
            )
        } catch {
            print("ArgusDesk config warning: \(error.localizedDescription)")
            return InitialDashboard(
                viewModel: .empty,
                localRefreshSeconds: AppConfig.defaultLocalRefreshSeconds,
                remoteRefreshSeconds: AppConfig.defaultRemoteRefreshSeconds,
                servers: [],
                configSourceName: "not configured"
            )
        }
    }

    /// Captures fresh local status and updates the overlay.
    private func refreshLocalStatus() {
        dashboardViewModel = dashboardViewModel.updating(local: localMonitor.snapshot())
        overlayWindowController?.update(viewModel: dashboardViewModel)
        updateMenuBar()
    }

    /// Starts the local refresh timer.
    private func startLocalRefreshTimer() {
        localRefreshTimer?.invalidate()

        let interval = TimeInterval(max(1, localRefreshSeconds))
        localRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLocalStatus()
            }
        }
    }

    /// Starts the remote server refresh loop.
    private func startRemoteRefreshTimer() {
        remoteRefreshTimer?.invalidate()

        let interval = TimeInterval(max(1, remoteRefreshSeconds))
        remoteRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRemoteStatus(severityEngine: SeverityEngine(thresholds: self?.thresholds ?? .default))
            }
        }
    }

    /// Refreshes remote server rows without overlapping runs.
    private func refreshRemoteStatus(severityEngine: SeverityEngine) {
        guard !serverConfigs.isEmpty, !isRemoteRefreshRunning else {
            return
        }

        isRemoteRefreshRunning = true
        updateMenuBar()
        let monitor = RemoteMonitor(
            servers: serverConfigs,
            severityEngine: severityEngine
        )

        Task {
            let serverStatuses = await monitor.refreshAll()
            await MainActor.run {
                self.isRemoteRefreshRunning = false
                self.notificationController.process(servers: serverStatuses)
                self.dashboardViewModel = self.dashboardViewModel.updating(
                    servers: serverStatuses,
                    lastRefresh: Self.refreshTimeFormatter.string(from: Date())
                )
                self.overlayWindowController?.update(viewModel: self.dashboardViewModel)
                self.updateMenuBar()
            }
        }
    }

    /// Pushes the latest dashboard summary into the menu bar item.
    private func updateMenuBar() {
        menuBarController?.update(
            dashboard: dashboardViewModel,
            isRefreshing: isRemoteRefreshRunning
        )
    }

    /// Opens the Preferences window, creating it on first use.
    private func showPreferences() {
        if let preferencesWindowController {
            preferencesWindowController.show()
            return
        }

        let preferences = AppPreferences(
            localRefreshSeconds: localRefreshSeconds,
            remoteRefreshSeconds: remoteRefreshSeconds,
            overlayWidth: overlayWidth,
            notificationsEnabled: notificationsEnabled,
            recoveryNotificationsEnabled: recoveryNotificationsEnabled,
            thresholds: .default
        )

        let controller = PreferencesWindowController(
            preferences: preferences,
            configSourceName: configSourceName,
            serverCount: serverConfigs.count,
            apply: { [weak self] preferences in
                self?.apply(preferences: preferences)
            }
        )
        preferencesWindowController = controller
        controller.show()
    }

    /// Persists preference changes and immediately restarts refresh timers.
    private func apply(preferences: AppPreferences) {
        preferencesStore.save(preferences)
        localRefreshSeconds = preferences.localRefreshSeconds
        remoteRefreshSeconds = preferences.remoteRefreshSeconds
        overlayWidth = preferences.overlayWidth
        overlayWindowController?.resize(width: overlayWidth)
        thresholds = preferences.thresholds
        notificationsEnabled = preferences.notificationsEnabled
        recoveryNotificationsEnabled = preferences.recoveryNotificationsEnabled
        notificationController.configure(
            notificationsEnabled: notificationsEnabled,
            recoveryNotificationsEnabled: recoveryNotificationsEnabled
        )
        dashboardViewModel = dashboardViewModel.updating(remoteRefreshSeconds: remoteRefreshSeconds)
        overlayWindowController?.update(viewModel: dashboardViewModel)
        updateMenuBar()
        startLocalRefreshTimer()
        startRemoteRefreshTimer()
    }

    /// Keeps the app running if the overlay is ever closed.
    ///
    /// Closing the Preferences window should not terminate the menu bar app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Startup result containing the first dashboard and refresh settings.
private struct InitialDashboard {
    /// Initial dashboard built from config or fallback data.
    let viewModel: DashboardViewModel

    /// Local refresh interval in seconds.
    let localRefreshSeconds: Int

    /// Remote refresh interval in seconds.
    let remoteRefreshSeconds: Int

    /// Configured servers for remote monitoring.
    let servers: [ServerConfig]

    /// Name of the JSON configuration source.
    let configSourceName: String
}

private extension AppDelegate {
    /// Shared formatter for compact refresh timestamps in the overlay header.
    static let refreshTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

