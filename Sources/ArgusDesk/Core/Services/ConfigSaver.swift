import Foundation

/// Writes ArgusDesk configuration back to the JSON file.
///
/// This is the counterpart to `ConfigLoader`. It serialises an `AppConfig`
/// into the same format the user originally configured, preserving any
/// fields not exposed by the editor (such as `http_user_agent`).
struct ConfigSaver {
    /// Updates only refresh fields, preserving unknown/custom configuration.
    /// Stale Settings cannot overwrite a different set of server connections.
    static func saveRefreshIntervals(to url: URL, values: [String: String], localLabel: String? = nil) -> String? {
        do {
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
            guard var servers = object["servers"] as? [[String: Any]] else { return "Configuration has no server list." }
            var changed = false
            if let localLabel {
                let trimmed = localLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                let value: String? = trimmed.isEmpty ? nil : trimmed
                if object["local_label"] as? String != value {
                    changed = true
                    object["local_label"] = value
                }
            }
            for index in servers.indices {
                let entry = servers[index]
                let key = "\(entry["ssh_user"] as? String ?? ServerConfig.defaultSSHUser)@\(entry["host"] as? String ?? ""):\(entry["ssh_port"] as? Int ?? ServerConfig.defaultSSHPort)"
                guard let text = values[key] else { return "Server configuration changed. Close and reopen Settings before editing refresh intervals." }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty || (Int(trimmed) ?? 0) > 0 else { return "Refresh intervals must be blank or positive whole seconds." }
                let value = Int(trimmed)
                if entry["refresh_seconds"] as? Int != value || (value == nil && entry["refresh_seconds"] != nil) {
                    changed = true
                    servers[index]["refresh_seconds"] = value
                }
            }
            if changed {
                object["servers"] = servers
                let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url, options: .atomic)
            }
            return nil
        } catch { return "Could not save server refresh intervals: \(error.localizedDescription)" }
    }

    /// Serialises the configuration back to JSON and writes it to disk.
    ///
    /// Returns an error string on failure, or nil on success.
    static func save(
        to fileURL: URL,
        config: AppConfig
    ) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.keyEncodingStrategy = .convertToSnakeCase

        do {
            let data = try encoder.encode(config)
            try data.write(to: fileURL, options: [.withoutOverwriting])
            return nil
        } catch {
            return "Failed to save configuration: \(error.localizedDescription)"
        }
    }
}
