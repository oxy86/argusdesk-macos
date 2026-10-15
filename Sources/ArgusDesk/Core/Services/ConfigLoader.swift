import Foundation
import SwiftUI

/// Loads local ArgusDesk configuration from the project/app directory.
///
/// `servers.example.json` is documentation only and is never treated as live
/// configuration. The loader intentionally does not watch for file changes;
/// live reload is tracked in the roadmap.
struct ConfigLoader {
    /// Local configuration file name used when no explicit path is set.
    private let configFileName = "servers.json"

    /// File manager used for existence checks and file reads.
    private let fileManager: FileManager

    /// Directory URLs where config files may live when no explicit path is set.
    private let searchDirectories: [URL]

    /// All validation errors and warnings for the loaded configuration.
    private var validation = ConfigValidation()

    /// Creates a loader rooted around the process working directory.
    ///
    /// SwiftPM runs the executable from the package directory, which makes this
    /// enough for development. The executable directory is also included so a
    /// future app bundle or copied binary has a second practical lookup path.
    ///
    /// - Parameters:
    ///   - fileManager: The file manager to use for filesystem operations.
    ///   - currentDirectory: The working directory to search.
    ///   - executableURL: The directory next to the executable to search.
    init(
        fileManager: FileManager = .default,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        executableURL: URL = Bundle.main.bundleURL.deletingLastPathComponent()
    ) {
        self.fileManager = fileManager
        searchDirectories = [
            currentDirectory,
            executableURL
        ]
    }

    /// Loads and decodes local configuration.
    ///
    /// - Parameters:
    ///   - explicitPath: An absolute path to a JSON config file, or nil to
    ///     search the default directories.
    /// - Returns: A decoded configuration along with metadata.
    /// - Throws: ConfigLoaderError.noConfigFileFound if no file is available.
    mutating func load(from explicitPath: String?) throws -> LoadedConfig {
        // If the user provided an explicit path, try that first.
        if let path = explicitPath {
            let url = URL(fileURLWithPath: path)
            guard fileManager.fileExists(atPath: url.path) else {
                throw ConfigLoaderError.configFileNotFound(url.path)
            }

            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            validate(config)
            return LoadedConfig(config: config, sourceURL: url, validation: validation)
        }

        // Otherwise search the default directories.
        for directory in searchDirectories {
            let url = directory.appendingPathComponent(configFileName)

            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            validate(config)
            return LoadedConfig(config: config, sourceURL: url, validation: validation)
        }

        throw ConfigLoaderError.noConfigFileFound(configFileName)
    }

    /// Validates the given configuration and populates `validation`.
    ///
    /// Called after successful decode so the UI can surface config problems
    /// without crashing the app.
    private mutating func validate(_ config: AppConfig) {
        validation = ConfigValidation()

        guard !config.servers.isEmpty else {
            validation.warnings.append("No servers configured.")
            return
        }

        for (index, server) in config.servers.enumerated() {
            validate(server, index: index)
        }
    }

    /// Validates a single server configuration entry.
    private mutating func validate(_ server: ServerConfig, index: Int) {
        let name = server.displayName.trimmingCharacters(in: .whitespaces)
        let host = server.host.trimmingCharacters(in: .whitespaces)

        // Ensure server name is present and not just whitespace.
        if name.isEmpty {
            validation.errors.append("Server at index \(index) has an empty name.")
        }

        // Ensure host is present and not just whitespace.
        if host.isEmpty {
            let displayName = name.isEmpty ? "(unnamed)" : name
            validation.errors.append("Server \"\(displayName)\" has an empty host.")
        }

        // Validate that every enabledChecks entry is a known key.
        let unknownChecks = Set(server.enabledChecks).subtracting(knownCheckKeys)
        if !unknownChecks.isEmpty {
            let checks = unknownChecks.sorted().joined(separator: ", ")
            validation.warnings.append(
                "Server \"\(name.isEmpty ? "(unnamed)" : name)\" has unknown check identifiers: \(checks)"
            )
        }

        // If the server has an HTTP URL, verify it parses correctly.
        if server.httpURL == nil, server.enabledChecks.contains("http") {
            validation.warnings.append(
                "Server \"\(name.isEmpty ? "(unnamed)" : name)\" has \"http\" in enabledChecks but no valid \"http_url\"."
            )
        }

        // If enabledChecks is completely empty, warn that nothing will be checked.
        if server.enabledChecks.isEmpty {
            validation.warnings.append(
                "Server \"\(name.isEmpty ? "(unnamed)" : name)\" has no enabledChecks; no checks will run."
            )
        }
    }
}

/// A decoded configuration plus the file it came from.
struct LoadedConfig {
    /// Decoded app configuration.
    let config: AppConfig

    /// Source file used for this config.
    let sourceURL: URL

    /// Validation warnings and errors discovered while loading.
    let validation: ConfigValidation
}

/// Configuration problems discovered during loading or validation.
struct ConfigValidation {
    /// Errors that indicate a problem worth surfacing to the user.
    var errors: [String] = []

    /// Warnings that indicate a potential issue but are not critical.
    var warnings: [String] = []

    /// Whether there are any problems to report.
    var hasProblems: Bool {
        !errors.isEmpty || !warnings.isEmpty
    }

    /// All problem messages combined.
    var allMessages: [String] {
        errors + warnings
    }
}

/// Errors that can occur before monitoring starts.
enum ConfigLoaderError: LocalizedError {
    /// No supported configuration file existed in any search directory.
    case noConfigFileFound(String)

    /// The user-specified configuration file does not exist.
    case configFileNotFound(String)

    /// Human-readable message shown in development logs and future UI.
    var errorDescription: String? {
        switch self {
        case .noConfigFileFound(let fileName):
            "No configuration file found. Expected \(fileName)."
        case .configFileNotFound(let path):
            "Configuration file not found: \(path)."
        }
    }
}
