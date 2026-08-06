import Foundation

/// Writes ArgusDesk configuration back to the JSON file.
///
/// This is the counterpart to `ConfigLoader`. It serialises an `AppConfig`
/// into the same format the user originally configured, preserving any
/// fields not exposed by the editor (such as `http_user_agent`).
struct ConfigSaver {
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
