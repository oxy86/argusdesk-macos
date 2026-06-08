import Foundation

/// Runs a local HTTP HEAD check with the system curl executable.
struct HTTPChecker {
    /// Shared command runner.
    private let commandRunner: CommandRunner

    /// Creates an HTTP checker.
    init(commandRunner: CommandRunner = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// Checks the configured URL and returns a compact HTTP metric.
    func check(url: URL?, userAgent: String?) -> Metric {
        guard let url else {
            return Metric(label: "http", value: "n/a", severity: .unknown)
        }

        var arguments = ["-Is", "--max-time", "2"]
        if let userAgent, !userAgent.isEmpty {
            arguments += ["-A", userAgent]
        }
        arguments.append(url.absoluteString)

        let result = commandRunner.run(
            executable: "/usr/bin/curl",
            arguments: arguments,
            timeoutSeconds: 3
        )

        guard result.succeeded else {
            return Metric(label: "http", value: result.timedOut ? "timeout" : "fail", severity: .error)
        }

        guard let statusCode = parseStatusCode(from: result.stdout) else {
            return Metric(label: "http", value: "unknown", severity: .unknown)
        }

        let severity: Severity = statusCode == 200 ? .ok : .warning
        return Metric(label: "http", value: "\(statusCode)", severity: severity)
    }

    /// Reads the last HTTP status line, which accounts for redirects or proxy hops.
    private func parseStatusCode(from output: String) -> Int? {
        let statusLines = output
            .split(separator: "\n")
            .filter { $0.hasPrefix("HTTP/") }

        guard let line = statusLines.last else {
            return nil
        }

        let pieces = line.split(separator: " ")
        guard pieces.count >= 2 else {
            return nil
        }

        return Int(pieces[1])
    }
}
