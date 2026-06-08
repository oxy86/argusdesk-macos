import Foundation

/// Runs a local macOS ping check for one configured host.
struct PingChecker {
    /// Shared command runner.
    private let commandRunner: CommandRunner

    /// Creates a ping checker.
    init(commandRunner: CommandRunner = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// Sends one ICMP packet and returns a compact metric.
    func check(host: String) -> Metric {
        let result = commandRunner.run(
            executable: "/sbin/ping",
            arguments: ["-c", "1", "-t", "2", host],
            timeoutSeconds: 3
        )

        guard result.succeeded else {
            return Metric(label: "ping", value: result.timedOut ? "timeout" : "fail", severity: .error)
        }

        if let latency = parseLatency(from: result.stdout) {
            return Metric(label: "ping", value: latency, severity: .ok)
        }

        return Metric(label: "ping", value: "ok", severity: .ok)
    }

    /// Extracts the `time=... ms` value from ping output.
    private func parseLatency(from output: String) -> String? {
        guard let range = output.range(of: "time=") else {
            return nil
        }

        let suffix = output[range.upperBound...]
        let value = suffix.prefix { character in
            character != " " && character != "\n"
        }

        guard !value.isEmpty else {
            return nil
        }

        return "\(value)ms"
    }
}
