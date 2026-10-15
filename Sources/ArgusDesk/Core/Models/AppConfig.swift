import Foundation

/// Known check identifiers that servers.json may list in enabledChecks.
///
/// These are the only identifiers the monitoring engine recognises. Unknown
/// identifiers produce a validation warning instead of silently running.
let knownCheckKeys: Set<String> = [
    "ssh", "ping", "http", "load", "disk", "memory",
    "nginx", "mariadb", "php_fpm", "memcached", "gpu"
]

/// Top-level configuration loaded from `servers.json` or `servers.example.json`.
///
/// Configuration shapes remote monitoring and default refresh intervals.
struct AppConfig: Decodable, Encodable {
    /// Default remote refresh interval when the config omits it.
    static let defaultRemoteRefreshSeconds = 60

    /// Default local refresh interval when the config omits it.
    static let defaultLocalRefreshSeconds = 5

    /// Configured remote refresh interval in seconds.
    let remoteRefreshSeconds: Int

    /// Configured local refresh interval in seconds.
    let localRefreshSeconds: Int

    /// Servers that should appear in the remote monitoring section.
    let servers: [ServerConfig]

    /// Optional friendly name for the local Mac; blank uses its hostname.
    let localLabel: String?

    /// Decoding keys match the snake_case JSON format documented in README.
    private enum CodingKeys: String, CodingKey {
        case localLabel = "local_label"
        case remoteRefreshSeconds = "remote_refresh_seconds"
        case localRefreshSeconds = "local_refresh_seconds"
        case servers
    }

    /// Encoding keys also use snake_case for JSON output.
    private enum EncodedCodingKeys: String, CodingKey {
        case localLabel = "local_label"
        case remoteRefreshSeconds = "remote_refresh_seconds"
        case localRefreshSeconds = "local_refresh_seconds"
        case servers
    }

    /// Applies safe defaults while decoding optional top-level settings.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        remoteRefreshSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .remoteRefreshSeconds
        ) ?? Self.defaultRemoteRefreshSeconds

        localRefreshSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .localRefreshSeconds
        ) ?? Self.defaultLocalRefreshSeconds

        servers = try container.decodeIfPresent([ServerConfig].self, forKey: .servers) ?? []
        localLabel = try container.decodeIfPresent(String.self, forKey: .localLabel)
    }

    /// Creates an AppConfig with the given values.
    ///
    /// Convenience initialiser for constructing fallback configurations
    /// at runtime without JSON encoding/decoding.
    init(
        remoteRefreshSeconds: Int = Self.defaultRemoteRefreshSeconds,
        localRefreshSeconds: Int = Self.defaultLocalRefreshSeconds,
        servers: [ServerConfig] = [],
        localLabel: String? = nil
    ) {
        self.remoteRefreshSeconds = remoteRefreshSeconds
        self.localRefreshSeconds = localRefreshSeconds
        self.servers = servers
        self.localLabel = localLabel
    }
}

/// One remote Linux server entry from the JSON configuration.
///
/// Defaults are intentionally conservative. The app never stores or accepts SSH
/// passwords; the username and port only control key-based SSH targets.
struct ServerConfig: Decodable, Encodable {
    /// Generic fallback SSH user when a server entry omits `ssh_user`.
    ///
    /// Real projects should set `ssh_user` in local `servers.json` or a future
    /// preferences layer. Public source must not contain personal usernames.
    static let defaultSSHUser = "username"

    /// Default SSH port when a server entry omits `ssh_port`.
    static let defaultSSHPort = 22

    /// Short human-readable name displayed in the window.
    let name: String

    /// Optional friendly display name; blank/missing labels use the host.
    let label: String?
    var displayName: String {
        let value = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? host : value
    }

    /// Hostname or IP address used for SSH, ping, and optional HTTP checks.
    let host: String

    /// SSH username for key-based authentication.
    let sshUser: String

    /// SSH port for key-based authentication.
    let sshPort: Int

    /// Optional URL checked locally with curl.
    let httpURL: URL?

    /// Optional User-Agent header used for the local HTTP check.
    let httpUserAgent: String?

    /// Enabled check identifiers from the config.
    let enabledChecks: [String]

    /// Nil means use the global remote refresh interval from Preferences.
    let refreshSeconds: Int?

    /// Stable identity for scheduling independently of display-name changes.
    var connectionID: String { "\(sshUser)@\(host):\(sshPort)" }

    func effectiveRefreshSeconds(global: Int) -> Int { refreshSeconds ?? max(1, global) }

    /// Decoding keys match the snake_case JSON format documented in README.
    private enum CodingKeys: String, CodingKey {
        case label
        case refreshSeconds = "refresh_seconds"
        case name
        case host
        case sshUser = "ssh_user"
        case sshPort = "ssh_port"
        case httpURL = "http_url"
        case httpUserAgent = "http_user_agent"
        case enabledChecks = "enabled_checks"
    }

    /// Creates a server config with all fields set explicitly.
    ///
    /// Convenience initialiser used by the server editor so the user can
    /// build a `ServerConfig` from the Preferences dialog without JSON.
    init(
        name: String,
        host: String,
        sshUser: String,
        sshPort: Int,
        httpURL: URL?,
        httpUserAgent: String?,
        enabledChecks: [String],
        refreshSeconds: Int? = nil,
        label: String? = nil
    ) {
        self.name = name
        self.label = label
        self.host = host
        self.sshUser = sshUser
        self.sshPort = sshPort
        self.httpURL = httpURL
        self.httpUserAgent = httpUserAgent
        self.enabledChecks = enabledChecks
        self.refreshSeconds = refreshSeconds
    }

    /// Applies defaults for optional SSH settings and keeps HTTP optional.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        host = try container.decode(String.self, forKey: .host)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? host
        label = try container.decodeIfPresent(String.self, forKey: .label)
        sshUser = try container.decodeIfPresent(String.self, forKey: .sshUser) ?? Self.defaultSSHUser
        sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort) ?? Self.defaultSSHPort
        httpUserAgent = try container.decodeIfPresent(String.self, forKey: .httpUserAgent)
        enabledChecks = try container.decodeIfPresent([String].self, forKey: .enabledChecks) ?? []

        if try !container.contains(.refreshSeconds) || container.decodeNil(forKey: .refreshSeconds) {
            refreshSeconds = nil
        } else if let seconds = try? container.decode(Int.self, forKey: .refreshSeconds), seconds > 0 {
            refreshSeconds = seconds
        } else if let text = try? container.decode(String.self, forKey: .refreshSeconds) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { refreshSeconds = nil }
            else if let seconds = Int(trimmed), seconds > 0 { refreshSeconds = seconds }
            else { throw DecodingError.dataCorruptedError(forKey: .refreshSeconds, in: container, debugDescription: "Refresh must be blank or a positive whole number of seconds.") }
        } else {
            throw DecodingError.dataCorruptedError(forKey: .refreshSeconds, in: container, debugDescription: "Refresh must be blank or a positive whole number of seconds.")
        }

        if let rawURL = try container.decodeIfPresent(String.self, forKey: .httpURL) {
            httpURL = URL(string: rawURL)
        } else {
            httpURL = nil
        }
    }
}
