import Foundation

/// Editable representation of a single server configuration entry.
///
/// Used by the Preferences window so the user can modify server details
/// without manually editing the JSON file. The editor is converted back
/// to `ServerConfig` when saving.
struct ServerEditor: Identifiable {
    /// Stable identity for SwiftUI rendering.
    let id = UUID()

    /// Short human-readable name displayed in the window.
    var name: String

    /// Hostname or IP address for SSH, ping, and HTTP checks.
    var host: String

    /// SSH username for key-based authentication.
    var sshUser: String

    /// SSH port for key-based authentication.
    var sshPort: Int

    /// Optional HTTP URL checked locally with curl.
    var httpURL: String?

    /// Optional HTTP User-Agent header.
    var httpUserAgent: String?

    /// Enabled check identifiers from the config.
    var enabledChecks: [String]

    /// Optional per-server refresh override.
    var refreshSeconds: Int?

    /// Creates an editor from an existing `ServerConfig`.
    init(from config: ServerConfig) {
        self.name = config.label ?? ""
        self.host = config.host
        self.sshUser = config.sshUser
        self.sshPort = config.sshPort
        self.httpURL = config.httpURL?.absoluteString
        self.httpUserAgent = config.httpUserAgent
        self.enabledChecks = config.enabledChecks
        self.refreshSeconds = config.refreshSeconds
    }

    /// Creates a blank new server editor with defaults.
    init() {
        self.name = ""
        self.host = ""
        self.sshUser = ServerConfig.defaultSSHUser
        self.sshPort = ServerConfig.defaultSSHPort
        self.httpURL = nil
        self.httpUserAgent = nil
        self.enabledChecks = []
        self.refreshSeconds = nil
    }
}

/// Converts an editable server back into a runtime `ServerConfig`.
extension ServerEditor {
    /// Attempts to create a `ServerConfig` from the current editor values.
    ///
    /// Returns nil when the server name or host is missing, since those
    /// are required for any meaningful monitoring.
    func toConfig() -> ServerConfig? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)

        guard !trimmedHost.isEmpty else {
            return nil
        }

        var parsedHTTPURL: URL? = nil
        if let rawURL = self.httpURL, !rawURL.isEmpty {
            parsedHTTPURL = URL(string: rawURL)
        }

        return ServerConfig(
            name: trimmedName,
            host: trimmedHost,
            sshUser: sshUser,
            sshPort: sshPort,
            httpURL: parsedHTTPURL,
            httpUserAgent: httpUserAgent,
            enabledChecks: enabledChecks,
            refreshSeconds: refreshSeconds,
            label: trimmedName.isEmpty ? nil : trimmedName
        )
    }
}

/// Validation errors for a single server editor.
struct ServerValidation: Identifiable {
    let id = UUID()
    let message: String

    /// Validates the current editor values and returns zero or one error.
    ///
    /// A blank name or host is always an error. Other issues are warnings.
    static func validate(editor: ServerEditor) -> ServerValidation? {
        let trimmedHost = editor.host.trimmingCharacters(in: .whitespaces)

        if trimmedHost.isEmpty {
            return ServerValidation(message: "Server host is required.")
        }

        return nil
    }
}
