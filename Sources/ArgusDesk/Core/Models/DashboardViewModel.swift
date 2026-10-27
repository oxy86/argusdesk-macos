import Foundation

/// Complete data snapshot rendered by the dashboard.
struct DashboardViewModel {
    /// Local Mac status shown at the top of the window.
    let local: LocalStatus

    /// Remote server summaries shown as the primary body of the widget.
    let servers: [ServerStatus]

    /// Human-readable refresh time shown in the header.
    let lastRefresh: String

    /// Human-readable remote refresh interval shown near the server list.
    let remoteRefreshInterval: String

    /// Validation problems discovered when loading configuration.
    ///
    /// nil means the config has not been loaded yet. An empty but non-nil
    /// value means the config is valid and there are no warnings.
    let configValidation: ConfigValidation?

    /// Creates a copy with fresh local Mac status.
    ///
    /// Keeping this as a value-model helper lets the AppKit timer replace just
    /// the local section without changing the latest remote rows.
    func updating(local newLocalStatus: LocalStatus) -> DashboardViewModel {
        DashboardViewModel(
            local: newLocalStatus,
            servers: servers,
            lastRefresh: lastRefresh,
            remoteRefreshInterval: remoteRefreshInterval,
            configValidation: configValidation
        )
    }

    /// Creates a copy with fresh remote server status.
    ///
    /// The remote refresh loop uses this to update server rows while preserving
    /// the most recent local Mac status.
    func updating(servers newServers: [ServerStatus], lastRefresh newLastRefresh: String) -> DashboardViewModel {
        DashboardViewModel(
            local: local,
            servers: newServers,
            lastRefresh: newLastRefresh,
            remoteRefreshInterval: remoteRefreshInterval,
            configValidation: configValidation
        )
    }

    /// Creates a copy with a new displayed remote refresh interval.
    func updating(remoteRefreshSeconds: Int) -> DashboardViewModel {
        DashboardViewModel(
            local: local,
            servers: servers,
            lastRefresh: lastRefresh,
            remoteRefreshInterval: "\(remoteRefreshSeconds)s",
            configValidation: configValidation
        )
    }

    /// Creates a copy with a new config, fresh pending servers, and new validation.
    ///
    /// Called when the user changes the configuration file path in Preferences.
    /// Preserves local Mac status and resets the timestamp for the new server list.
    func replacing(
        config: AppConfig,
        servers: [ServerConfig],
        validation: ConfigValidation?
    ) -> DashboardViewModel {
        DashboardViewModel(
            local: local,
            servers: servers.map(ServerStatus.pending(from:)),
            lastRefresh: "not refreshed",
            remoteRefreshInterval: "\(config.remoteRefreshSeconds)s",
            configValidation: validation
        )
    }

    /// Empty startup state used until configuration and live data are available.
    static let empty = DashboardViewModel(
        local: LocalStatus(
            hostname: "local",
            osVersion: "macOS",
            uptime: "-",
            battery: "-",
            cpu: "-",
            memory: "-",
            disk: "-",
            network: "-"
        ),
        servers: [],
        lastRefresh: "not refreshed",
        remoteRefreshInterval: "\(AppConfig.defaultRemoteRefreshSeconds)s",
        configValidation: nil
    )

    /// Builds the initial pending dashboard from loaded configuration.
    static func pending(
        config: AppConfig,
        configSource: URL,
        validation: ConfigValidation?
    ) -> DashboardViewModel {
        return DashboardViewModel(
            local: empty.local,
            servers: config.servers.map(ServerStatus.pending(from:)),
            lastRefresh: "not refreshed",
            remoteRefreshInterval: "\(config.remoteRefreshSeconds)s",
            configValidation: validation
        )
    }
}

/// Local Mac metrics displayed by the overlay.
///
/// Values are strings because the current Window displays compact formatted
/// text. Later services can introduce numeric raw values where thresholds or
/// formatting require them.
struct LocalStatus {
    /// Short host name for the current Mac.
    let hostname: String

    /// Human-readable macOS version.
    let osVersion: String

    /// Human-readable uptime.
    let uptime: String

    /// Battery percentage or status text.
    let battery: String

    /// CPU usage summary.
    let cpu: String

    /// Memory usage summary.
    let memory: String

    /// Disk usage summary.
    let disk: String

    /// Wi-Fi and IP information.
    let network: String

    /// Allocated swap and sampled disk busy time; n/a means unsupported.
    var swap: String = "-"
    var diskBusy: String = "n/a"
}

/// Display state for one remote server.
///
/// This model is intentionally UI-friendly and is populated by remote monitoring.
struct ServerStatus: Identifiable {
    /// Only enabled body metrics are rendered; heading checks stay separate.
    var visibleMetrics: [Metric] {
        metrics.filter { !["ssh", "ping", "http"].contains($0.label) && $0.value != "off" }
    }

    /// Stable identity for SwiftUI rendering.
    let id = UUID()

    /// Short display name for the server row.
    let name: String

    /// Worst current state for the server.
    let severity: Severity

    /// One-line summary shown next to the server name.
    let headline: String

    /// Compact metric rows shown under the server header.
    let metrics: [Metric]

    /// Effective interval shown beneath each independently refreshed card.
    var refreshInterval: String? = nil

    /// Time this server last returned a completed check, including failed checks.
    var lastResultAt: Date? = nil

    /// Creates a pending server row before the first remote refresh completes.
    static func pending(from config: ServerConfig) -> ServerStatus {
        let httpValue = config.httpURL == nil ? "n/a" : "pending"

        return ServerStatus(
            name: config.displayName,
            severity: .unknown,
            headline: "\(config.host)  pending",
            metrics: [
                pendingMetric(label: "ssh", key: "ssh", config: config),
                pendingMetric(label: "ping", key: "ping", config: config),
                pendingMetric(label: "http", key: "http", config: config, value: httpValue),
                pendingMetric(label: "load", key: "load", config: config),
                pendingMetric(label: "disk /", key: "disk", config: config),
                pendingMetric(label: "mem", key: "memory", config: config),
                pendingMetric(label: "nginx", key: "nginx", config: config),
                pendingMetric(label: "db", key: "mariadb", config: config),
                pendingMetric(label: "php-fpm", key: "php_fpm", config: config),
                pendingMetric(label: "memcached", key: "memcached", config: config),
                pendingMetric(label: "gpu", key: "gpu", config: config)
            ]
        )
    }

    /// Creates an unknown pending metric or an explicit disabled metric.
    private static func pendingMetric(
        label: String,
        key: String,
        config: ServerConfig,
        value: String = "pending"
    ) -> Metric {
        Metric(
            label: label,
            value: config.enabledChecks.contains(key) ? value : "off",
            severity: .unknown
        )
    }
}

/// One compact label/value/status row inside a server section.
struct Metric: Identifiable {
    /// Stable identity for SwiftUI rendering.
    let id = UUID()

    /// Short metric label, such as `ssh`, `ping`, or `disk /`.
    let label: String

    /// Already-formatted display value.
    let value: String

    /// Health state for this individual metric.
    let severity: Severity

    /// Raw NVIDIA readings avoid extracting percentages from formatted text.
    var gpuUtilizationPercent: Double? = nil
    var gpuMemoryUsagePercent: Double? = nil
}
