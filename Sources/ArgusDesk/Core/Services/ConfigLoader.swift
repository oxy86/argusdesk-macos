import Foundation

/// Loads local ArgusDesk configuration from the project/app directory.
///
/// `servers.example.json` is documentation only and is never treated as live
/// configuration. The loader intentionally does not watch for file changes;
/// live reload is tracked in the roadmap.
struct ConfigLoader {
    /// Local configuration file name.
    private let configFileName = "servers.json"

    /// File manager used for existence checks and file reads.
    private let fileManager: FileManager

    /// Directory URLs where config files may live.
    private let searchDirectories: [URL]

    /// Creates a loader rooted around the process working directory.
    ///
    /// SwiftPM runs the executable from the package directory, which makes this
    /// enough for development. The executable directory is also included so a
    /// future app bundle or copied binary has a second practical lookup path.
    init(
        fileManager: FileManager = .default,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        executableURL: URL = Bundle.main.bundleURL
    ) {
        self.fileManager = fileManager
        searchDirectories = [
            currentDirectory,
            executableURL.deletingLastPathComponent()
        ]
    }

    /// Loads and decodes local configuration.
    func load() throws -> LoadedConfig {
        for directory in searchDirectories {
            let url = directory.appendingPathComponent(configFileName)

            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            return LoadedConfig(config: config, sourceURL: url)
        }

        throw ConfigLoaderError.noConfigFileFound(configFileName)
    }
}

/// A decoded configuration plus the file it came from.
struct LoadedConfig {
    /// Decoded app configuration.
    let config: AppConfig

    /// Source file used for this config.
    let sourceURL: URL
}

/// Errors that can occur before monitoring starts.
enum ConfigLoaderError: LocalizedError {
    /// No supported configuration file existed in any search directory.
    case noConfigFileFound(String)

    /// Human-readable message shown in development logs and future UI.
    var errorDescription: String? {
        switch self {
        case .noConfigFileFound(let fileName):
            "No configuration file found. Expected \(fileName)."
        }
    }
}
