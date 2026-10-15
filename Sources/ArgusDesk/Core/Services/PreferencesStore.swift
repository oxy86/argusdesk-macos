import Foundation

/// User-editable ArgusDesk preferences persisted by macOS.
///
/// Server definitions remain in `servers.json`. This store only persists
/// lightweight app behavior and notification settings appropriate for
/// `UserDefaults`.
struct AppPreferences {
    /// Local Mac status refresh interval in seconds.
    let localRefreshSeconds: Int

    /// Remote server refresh interval in seconds.
    let remoteRefreshSeconds: Int

    /// Window width in points.
    let overlayWidth: Int

    /// Path to the JSON configuration file, or nil to use the default search.
    let configFilePath: String?

    /// Whether warning/error notifications are enabled.
    let notificationsEnabled: Bool

    /// Whether recovery notifications are enabled.
    let recoveryNotificationsEnabled: Bool

    /// Severity thresholds that control when checks report warnings or errors.
    let thresholds: Thresholds
}

/// Configurable severity thresholds for monitoring metrics.
struct Thresholds: Sendable {
    /// Ping latency (ms) above which the metric is degraded.
    let pingWarningMilliseconds: Double

    /// Ping latency (ms) above which the metric is critical.
    let pingErrorMilliseconds: Double

    /// Disk or memory usage (%) above which the metric is degraded.
    let usageWarningPercent: Double

    /// Disk or memory usage (%) above which the metric is critical.
    let usageErrorPercent: Double

    /// Service CPU (%) above which the metric is degraded.
    let serviceCPUWarningPercent: Double

    /// Service CPU (%) above which the metric is critical.
    let serviceCPUErrorPercent: Double

    /// PHP-FPM has independent CPU limits; other services use the shared limits.
    let phpFPMCPUWarningPercent: Double
    let phpFPMCPUErrorPercent: Double

    /// GPU compute utilization and VRAM occupancy have independent limits.
    let gpuWarningPercent: Double
    let gpuErrorPercent: Double
    let gpuMemoryWarningPercent: Double
    let gpuMemoryErrorPercent: Double

    /// Creates thresholds with default (conservative) values.
    static let `default` = Thresholds(
        pingWarningMilliseconds: 200,
        pingErrorMilliseconds: 1000,
        usageWarningPercent: 80,
        usageErrorPercent: 90,
        serviceCPUWarningPercent: 10,
        serviceCPUErrorPercent: 25
    )

    /// Creates thresholds with the given values.
    init(
        pingWarningMilliseconds: Double = 200,
        pingErrorMilliseconds: Double = 1000,
        usageWarningPercent: Double = 80,
        usageErrorPercent: Double = 90,
        serviceCPUWarningPercent: Double = 10,
        serviceCPUErrorPercent: Double = 25,
        phpFPMCPUWarningPercent: Double = 50,
        phpFPMCPUErrorPercent: Double = 90,
        gpuWarningPercent: Double = 80,
        gpuErrorPercent: Double = 95,
        gpuMemoryWarningPercent: Double = 80,
        gpuMemoryErrorPercent: Double = 95
    ) {
        self.pingWarningMilliseconds = pingWarningMilliseconds
        self.pingErrorMilliseconds = pingErrorMilliseconds
        self.usageWarningPercent = usageWarningPercent
        self.usageErrorPercent = usageErrorPercent
        self.serviceCPUWarningPercent = serviceCPUWarningPercent
        self.serviceCPUErrorPercent = serviceCPUErrorPercent
        self.phpFPMCPUWarningPercent = phpFPMCPUWarningPercent
        self.phpFPMCPUErrorPercent = phpFPMCPUErrorPercent
        self.gpuWarningPercent = gpuWarningPercent
        self.gpuErrorPercent = gpuErrorPercent
        self.gpuMemoryWarningPercent = gpuMemoryWarningPercent
        self.gpuMemoryErrorPercent = gpuMemoryErrorPercent
    }
}

/// Reads and writes app preferences with `UserDefaults`.
struct PreferencesStore {
    /// Keys owned by ArgusDesk in the defaults database.
    private enum Key {
        static let localRefreshSeconds = "localRefreshSeconds"
        static let remoteRefreshSeconds = "remoteRefreshSeconds"
        static let overlayWidth = "overlayWidth"
        static let configFilePath = "configFilePath"
        static let notificationsEnabled = "notificationsEnabled"
        static let recoveryNotificationsEnabled = "recoveryNotificationsEnabled"
        static let pingWarningMilliseconds = "pingWarningMilliseconds"
        static let pingErrorMilliseconds = "pingErrorMilliseconds"
        static let usageWarningPercent = "usageWarningPercent"
        static let usageErrorPercent = "usageErrorPercent"
        static let serviceCPUWarningPercent = "serviceCPUWarningPercent"
        static let serviceCPUErrorPercent = "serviceCPUErrorPercent"
        static let phpFPMCPUWarningPercent = "phpFPMCPUWarningPercent"
        static let phpFPMCPUErrorPercent = "phpFPMCPUErrorPercent"
        static let gpuWarningPercent = "gpuWarningPercent"
        static let gpuErrorPercent = "gpuErrorPercent"
        static let gpuMemoryWarningPercent = "gpuMemoryWarningPercent"
        static let gpuMemoryErrorPercent = "gpuMemoryErrorPercent"
    }

    /// Defaults database used for persistence.
    private let defaults: UserDefaults

    /// Creates a preferences store.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Loads stored values, falling back to the current JSON configuration.
    func load(fallback: AppPreferences) -> AppPreferences {
        AppPreferences(
            localRefreshSeconds: positiveInteger(forKey: Key.localRefreshSeconds) ?? fallback.localRefreshSeconds,
            remoteRefreshSeconds: positiveInteger(forKey: Key.remoteRefreshSeconds) ?? fallback.remoteRefreshSeconds,
            overlayWidth: positiveInteger(forKey: Key.overlayWidth) ?? fallback.overlayWidth,
            configFilePath: storedString(forKey: Key.configFilePath) ?? fallback.configFilePath,
            notificationsEnabled: storedBoolean(forKey: Key.notificationsEnabled) ?? fallback.notificationsEnabled,
            recoveryNotificationsEnabled: storedBoolean(forKey: Key.recoveryNotificationsEnabled) ?? fallback.recoveryNotificationsEnabled,
            thresholds: Thresholds(
                pingWarningMilliseconds: storedDouble(forKey: Key.pingWarningMilliseconds, default: fallback.thresholds.pingWarningMilliseconds),
                pingErrorMilliseconds: storedDouble(forKey: Key.pingErrorMilliseconds, default: fallback.thresholds.pingErrorMilliseconds),
                usageWarningPercent: storedDouble(forKey: Key.usageWarningPercent, default: fallback.thresholds.usageWarningPercent),
                usageErrorPercent: storedDouble(forKey: Key.usageErrorPercent, default: fallback.thresholds.usageErrorPercent),
                serviceCPUWarningPercent: storedDouble(forKey: Key.serviceCPUWarningPercent, default: fallback.thresholds.serviceCPUWarningPercent),
                serviceCPUErrorPercent: storedDouble(forKey: Key.serviceCPUErrorPercent, default: fallback.thresholds.serviceCPUErrorPercent),
                phpFPMCPUWarningPercent: storedDouble(forKey: Key.phpFPMCPUWarningPercent,
                    default: fallback.thresholds.phpFPMCPUWarningPercent),
                phpFPMCPUErrorPercent: storedDouble(forKey: Key.phpFPMCPUErrorPercent,
                    default: fallback.thresholds.phpFPMCPUErrorPercent),
                gpuWarningPercent: storedDouble(forKey: Key.gpuWarningPercent, default: fallback.thresholds.gpuWarningPercent),
                gpuErrorPercent: storedDouble(forKey: Key.gpuErrorPercent, default: fallback.thresholds.gpuErrorPercent),
                gpuMemoryWarningPercent: storedDouble(forKey: Key.gpuMemoryWarningPercent, default: fallback.thresholds.gpuMemoryWarningPercent),
                gpuMemoryErrorPercent: storedDouble(forKey: Key.gpuMemoryErrorPercent, default: fallback.thresholds.gpuMemoryErrorPercent)
            )
        )
    }

    /// Persists the current app preferences.
    func save(_ preferences: AppPreferences) {
        defaults.set(max(1, preferences.localRefreshSeconds), forKey: Key.localRefreshSeconds)
        defaults.set(max(1, preferences.remoteRefreshSeconds), forKey: Key.remoteRefreshSeconds)
        defaults.set(max(150, preferences.overlayWidth), forKey: Key.overlayWidth)
        if let path = preferences.configFilePath {
            defaults.set(path, forKey: Key.configFilePath)
        } else {
            defaults.removeObject(forKey: Key.configFilePath)
        }
        defaults.set(preferences.notificationsEnabled, forKey: Key.notificationsEnabled)
        defaults.set(preferences.recoveryNotificationsEnabled, forKey: Key.recoveryNotificationsEnabled)
        defaults.set(preferences.thresholds.pingWarningMilliseconds, forKey: Key.pingWarningMilliseconds)
        defaults.set(preferences.thresholds.pingErrorMilliseconds, forKey: Key.pingErrorMilliseconds)
        defaults.set(preferences.thresholds.usageWarningPercent, forKey: Key.usageWarningPercent)
        defaults.set(preferences.thresholds.usageErrorPercent, forKey: Key.usageErrorPercent)
        defaults.set(preferences.thresholds.serviceCPUWarningPercent, forKey: Key.serviceCPUWarningPercent)
        defaults.set(preferences.thresholds.serviceCPUErrorPercent, forKey: Key.serviceCPUErrorPercent)
        defaults.set(preferences.thresholds.phpFPMCPUWarningPercent, forKey: Key.phpFPMCPUWarningPercent)
        defaults.set(preferences.thresholds.phpFPMCPUErrorPercent, forKey: Key.phpFPMCPUErrorPercent)
        defaults.set(preferences.thresholds.gpuWarningPercent, forKey: Key.gpuWarningPercent)
        defaults.set(preferences.thresholds.gpuErrorPercent, forKey: Key.gpuErrorPercent)
        defaults.set(preferences.thresholds.gpuMemoryWarningPercent, forKey: Key.gpuMemoryWarningPercent)
        defaults.set(preferences.thresholds.gpuMemoryErrorPercent, forKey: Key.gpuMemoryErrorPercent)
    }

    /// Returns a stored positive integer, ignoring invalid defaults.
    private func positiveInteger(forKey key: String) -> Int? {
        guard defaults.object(forKey: key) != nil else {
            return nil
        }

        let value = defaults.integer(forKey: key)
        return value > 0 ? value : nil
    }

    /// Returns a stored string, ignoring invalid defaults.
    private func storedString(forKey key: String) -> String? {
        guard defaults.object(forKey: key) != nil else {
            return nil
        }

        return defaults.string(forKey: key)
    }

    /// Returns a stored double, ignoring invalid defaults.
    private func storedDouble(forKey key: String, default: Double) -> Double {
        guard defaults.object(forKey: key) != nil else {
            return `default`
        }

        return defaults.double(forKey: key)
    }

    /// Returns a stored Boolean only when the key has been explicitly saved.
    private func storedBoolean(forKey key: String) -> Bool? {
        guard defaults.object(forKey: key) != nil else {
            return nil
        }

        return defaults.bool(forKey: key)
    }
}
