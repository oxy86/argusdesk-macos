import Foundation

/// Complete data snapshot rendered by the dashboard.
struct DashboardViewModel {
    /// Local Mac status shown at the top of the overlay.
    let local: LocalStatus

    /// Remote server summaries shown as the primary body of the widget.
    let servers: [ServerStatus]

    /// Human-readable refresh time shown in the header.
    let lastRefresh: String

    /// Human-readable remote refresh interval shown near the server list.
    let remoteRefreshInterval: String

    /// Creates a copy with fresh local Mac status.
    ///
    /// Keeping this as a value-model helper lets the AppKit timer replace just
    /// the local section without changing the latest remote rows.
    func updating(local newLocalStatus: LocalStatus) -> DashboardViewModel {
        DashboardViewModel(
            local: newLocalStatus,
            servers: servers,
            lastRefresh: lastRefresh,
            remoteRefreshInterval: remoteRefreshInterval
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
            remoteRefreshInterval: remoteRefreshInterval
        )
    }

    /// Creates a copy with a new displayed remote refresh interval.
    func updating(remoteRefreshSeconds: Int) -> DashboardViewModel {
        DashboardViewModel(
            local: local,
            servers: servers,
            lastRefresh: lastRefresh,
            remoteRefreshInterval: "\(remoteRefreshSeconds)s"
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
        remoteRefreshInterval: "\(AppConfig.defaultRemoteRefreshSeconds)s"
    )

    /// Builds the initial pending dashboard from loaded configuration.
    static func pending(config: AppConfig, configSource: URL) -> DashboardViewModel {
        return DashboardViewModel(
            local: empty.local,
            servers: config.servers.map(ServerStatus.pending(from:)),
            lastRefresh: configSource.lastPathComponent,
            remoteRefreshInterval: "\(config.remoteRefreshSeconds)s"
        )
    }
}

/// Local Mac metrics displayed by the overlay.
///
/// Values are strings because the current overlay displays compact formatted
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
}

/// Display state for one remote server.
///
/// This model is intentionally UI-friendly and is populated by remote monitoring.
struct ServerStatus: Identifiable {
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

    /// Creates a pending server row before the first remote refresh completes.
    static func pending(from config: ServerConfig) -> ServerStatus {
        let httpValue = config.httpURL == nil ? "n/a" : "pending"

        return ServerStatus(
            name: config.name,
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
                pendingMetric(label: "memcached", key: "memcached", config: config)
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
}
