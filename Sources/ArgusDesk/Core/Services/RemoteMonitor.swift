import Foundation

/// Refreshes remote server status with local network checks and key-only SSH.
///
/// RemoteMonitor collects values while `SeverityEngine` decides whether each
/// metric and server is OK, degraded, failed, or unknown.
struct RemoteMonitor {
    /// Remote command timeout for the single SSH command.
    ///
    /// Service CPU uses a short one-second sample. The timeout leaves room for
    /// four selected services plus normal SSH startup overhead.
    private static let sshTimeoutSeconds: TimeInterval = 15

    /// Configured servers to refresh.
    private let servers: [ServerConfig]

    /// Shared command runner.
    private let commandRunner: CommandRunner

    /// Local ping checker.
    private let pingChecker: PingChecker

    /// Local HTTP checker.
    private let httpChecker: HTTPChecker

    /// Shared severity evaluator.
    private let severityEngine: SeverityEngine

    /// Creates a monitor for the configured servers.
    init(servers: [ServerConfig], commandRunner: CommandRunner = CommandRunner(), severityEngine: SeverityEngine) {
        self.servers = servers
        self.commandRunner = commandRunner
        pingChecker = PingChecker(commandRunner: commandRunner)
        httpChecker = HTTPChecker(commandRunner: commandRunner)
        self.severityEngine = severityEngine
    }

    /// Refreshes all configured servers concurrently.
    func refreshAll() async -> [ServerStatus] {
        await withTaskGroup(of: (Int, ServerStatus).self) { group in
            for (index, server) in servers.enumerated() {
                group.addTask {
                    let status = refresh(server: server)
                    return (index, status)
                }
            }

            var statuses = Array<ServerStatus?>(repeating: nil, count: servers.count)
            for await (index, status) in group {
                statuses[index] = status
            }

            return statuses.compactMap { $0 }
        }
    }

    /// Refreshes one server using ping, optional HTTP, and one SSH command.
    private func refresh(server: ServerConfig) -> ServerStatus {
        let enabledChecks = Set(server.enabledChecks)
        let pingMetric = enabledChecks.contains("ping")
            ? pingChecker.check(host: server.host)
            : Metric(label: "ping", value: "off", severity: .unknown)
        let httpMetric = enabledChecks.contains("http")
            ? httpChecker.check(url: server.httpURL, userAgent: server.httpUserAgent)
            : Metric(label: "http", value: "off", severity: .unknown)
        let needsSSH = !enabledChecks.isDisjoint(with: Self.sshCheckKeys)
        let sshResult = needsSSH
            ? runSSH(server: server)
            : CommandResult(exitCode: 0, stdout: "", stderr: "", timedOut: false)
        let remoteMetrics = parseRemoteMetrics(from: sshResult, enabledChecks: server.enabledChecks)

        let sshMetric: Metric
        if !enabledChecks.contains("ssh") {
            sshMetric = Metric(label: "ssh", value: "off", severity: .unknown)
        } else if sshResult.succeeded {
            sshMetric = Metric(label: "ssh", value: "ok", severity: .ok)
        } else {
            sshMetric = Metric(
                label: "ssh",
                value: sshResult.timedOut ? "timeout" : "fail",
                severity: .error
            )
        }

        let metrics = severityEngine.evaluate(metrics: [sshMetric, pingMetric, httpMetric] + remoteMetrics)
        let severity = severityEngine.serverSeverity(for: metrics)
        let headline = headline(host: server.host, metrics: metrics, severity: severity)

        return ServerStatus(
            name: server.name,
            severity: severity,
            headline: headline,
            metrics: metrics
        )
    }

    /// Runs the key-only SSH command for internal server metrics.
    private func runSSH(server: ServerConfig) -> CommandResult {
        commandRunner.run(
            executable: "/usr/bin/ssh",
            arguments: [
                "-o", "BatchMode=yes",
                "-o", "PasswordAuthentication=no",
                "-o", "ConnectTimeout=5",
                "-p", "\(server.sshPort)",
                "\(server.sshUser)@\(server.host)",
                Self.remoteCommand
            ],
            timeoutSeconds: Self.sshTimeoutSeconds
        )
    }

    /// Converts remote key-value output into dashboard metrics.
    private func parseRemoteMetrics(from result: CommandResult, enabledChecks: [String]) -> [Metric] {
        guard result.succeeded else {
            return [
                basicMetric(label: "load", key: "load", values: [:], enabledChecks: enabledChecks, missingValue: "-"),
                basicMetric(label: "disk /", key: "disk", values: [:], enabledChecks: enabledChecks, missingValue: "-"),
                basicMetric(label: "mem", key: "memory", valueKey: "mem", values: [:], enabledChecks: enabledChecks, missingValue: "-"),
                serviceMetric(label: "nginx", key: "nginx", values: [:], enabledChecks: enabledChecks),
                serviceMetric(label: "db", key: "mariadb", values: [:], enabledChecks: enabledChecks),
                serviceMetric(label: "php-fpm", key: "php_fpm", values: [:], enabledChecks: enabledChecks),
                serviceMetric(label: "memcached", key: "memcached", values: [:], enabledChecks: enabledChecks)
            ]
        }

        let values = parseKeyValues(result.stdout)

        return [
            basicMetric(label: "load", key: "load", values: values, enabledChecks: enabledChecks),
            basicMetric(label: "disk /", key: "disk", values: values, enabledChecks: enabledChecks),
            basicMetric(label: "mem", key: "memory", valueKey: "mem", values: values, enabledChecks: enabledChecks),
            serviceMetric(label: "nginx", key: "nginx", values: values, enabledChecks: enabledChecks),
            serviceMetric(label: "db", key: "mariadb", values: values, enabledChecks: enabledChecks),
            serviceMetric(label: "php-fpm", key: "php_fpm", values: values, enabledChecks: enabledChecks),
            serviceMetric(label: "memcached", key: "memcached", values: values, enabledChecks: enabledChecks)
        ]
    }

    /// Builds a basic remote metric while respecting `enabled_checks`.
    private func basicMetric(
        label: String,
        key: String,
        valueKey: String? = nil,
        values: [String: String],
        enabledChecks: [String],
        missingValue: String = "n/a"
    ) -> Metric {
        guard enabledChecks.contains(key) else {
            return Metric(label: label, value: "off", severity: .unknown)
        }

        let value = values[valueKey ?? key]
        return Metric(
            label: label,
            value: value ?? missingValue,
            severity: value == nil ? .unknown : .ok
        )
    }

    /// Builds one service metric from `systemctl is-active` output.
    private func serviceMetric(
        label: String,
        key: String,
        values: [String: String],
        enabledChecks: [String]
    ) -> Metric {
        guard enabledChecks.contains(key) else {
            return Metric(label: label, value: "off", severity: .unknown)
        }

        guard let value = values[key], !value.isEmpty else {
            return Metric(label: label, value: "n/a", severity: .unknown)
        }

        let state = value.split(separator: " ").first.map(String.init) ?? value

        return Metric(
            label: label,
            value: value,
            severity: state == "active" ? .ok : .error
        )
    }

    /// Parses `key=value` lines from the remote command.
    private func parseKeyValues(_ output: String) -> [String: String] {
        var values: [String: String] = [:]

        for line in output.split(separator: "\n") {
            let pieces = line.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else {
                continue
            }

            let key = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            values[key] = value
        }

        return values
    }

    /// Creates a compact server headline.
    private func headline(host: String, metrics: [Metric], severity: Severity) -> String {
        let pingValue = metrics.first { $0.label == "ping" }?.value
        let ping = pingValue.flatMap { $0 == "off" ? nil : $0 } ?? host
        let http = metrics.first { $0.label == "http" }?.value

        if let http, http != "n/a", http != "off" {
            return "\(ping)  HTTP \(http)"
        }

        return "\(ping)  \(severity.shortLabel)"
    }

    /// Read-only remote shell snippet that emits predictable key-value lines.
    private static let remoteCommand = """
    printf 'load='
    uptime | sed 's/^.*load averages*: //; s/^.*load average: //'
    df -P / | awk 'NR==2 {print "disk="$5}'
    if command -v free >/dev/null 2>&1; then free -m | awk '/^Mem:/ {printf "mem=%d%%\\n", ($3 * 100) / $2}'; else echo 'mem=n/a'; fi
    if command -v systemctl >/dev/null 2>&1; then
      hz="$(getconf CLK_TCK 2>/dev/null || echo 100)"
      cpus="$(nproc 2>/dev/null || echo 1)"
      read_ticks() {
        printf '%s\n' "$1" | while IFS= read -r pid; do
          awk '{print $14 + $15}' "/proc/$pid/stat" 2>/dev/null
        done | awk '{sum += $1} END {print sum + 0}'
      }
      svc_metric() {
        key="$1"
        unit="$2"
        if [ -z "$unit" ]; then
          printf '%s=unknown 0.00GB 0.0%%\n' "$key"
          return
        fi
        state="$(systemctl is-active "$unit" 2>/dev/null || true)"
        [ -n "$state" ] || state="unknown"
        pids="$(systemctl show "$unit" -p MainPID -p ControlPID --value 2>/dev/null | awk '$1 != "0" {print}')"
        cgroup="$(systemctl show "$unit" -p ControlGroup --value 2>/dev/null)"
        if [ -n "$cgroup" ] && [ -d "/sys/fs/cgroup$cgroup" ]; then
          cg_pids="$(cat "/sys/fs/cgroup$cgroup/cgroup.procs" 2>/dev/null || true)"
          pids="$pids
    $cg_pids"
        fi
        pids="$(printf '%s\n' "$pids" | awk 'NF' | sort -u)"
        if [ -z "$pids" ]; then
          printf '%s=%s 0.00GB 0.0%%\n' "$key" "$state"
          return
        fi
        rss_kb="$(printf '%s\n' "$pids" | while IFS= read -r pid; do
          awk '/^VmRSS:/ {print $2}' "/proc/$pid/status" 2>/dev/null
        done | awk '{sum += $1} END {print sum + 0}')"
        interval="1"
        ticks_a="$(read_ticks "$pids")"
        sleep "$interval"
        ticks_b="$(read_ticks "$pids")"
        stats="$(awk -v rss="$rss_kb" -v a="$ticks_a" -v b="$ticks_b" -v hz="$hz" -v interval="$interval" -v cpus="$cpus" 'BEGIN {
          if (cpus < 1) cpus = 1
          printf "%.2fGB %.1f%%", rss / 1048576, ((b - a) / hz) / interval / cpus * 100
        }')"
        printf '%s=%s %s\n' "$key" "$state" "$stats"
      }
      php_fpm_unit="$(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '$1 ~ /^php[0-9.]+-fpm\\.service$/ { sub(/\\.service$/, "", $1); print $1; exit }')"
      svc_metric nginx nginx
      svc_metric mariadb mariadb
      svc_metric php_fpm "$php_fpm_unit"
      svc_metric memcached memcached
    fi
    """

    /// Checks that require the remote SSH command.
    private static let sshCheckKeys: Set<String> = [
        "ssh",
        "load",
        "disk",
        "memory",
        "nginx",
        "mariadb",
        "php_fpm",
        "memcached"
    ]
}
