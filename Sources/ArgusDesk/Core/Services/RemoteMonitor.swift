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
            name: server.displayName,
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
                Self.remoteCommand(enabledChecks: Set(server.enabledChecks))
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
            ] + (enabledChecks.contains("gpu") ? [Metric(label: "gpu", value: "n/a", severity: .unknown)] : [])
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
        ] + (enabledChecks.contains("disk") ? [Metric(label: "disk busy", value: values["disk_busy"] ?? "n/a", severity: .unknown)] : [])
          + (enabledChecks.contains("memory") ? [Metric(label: "swap", value: values["swap"] ?? "n/a", severity: .unknown)] : [])
          + (enabledChecks.contains("gpu") ? NVIDIAMetrics().parse(result.stdout) : [])
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
    static func remoteCommand(enabledChecks: Set<String>) -> String {
        // Check identifiers are selected from known constants, never interpolated
        // from arbitrary configuration text into the remote shell.
        let services = [("nginx", "nginx"), ("mariadb", "mariadb"),
                        ("php_fpm", "\"$php_fpm_unit\""), ("memcached", "memcached")]
            .filter { enabledChecks.contains($0.0) }
            .map { "svc_metric \($0.0) \($0.1)" }.joined(separator: "\n")
        return """
    if [ "\(enabledChecks.contains("load") ? "1" : "0")" = "1" ]; then
      printf 'load='
      uptime | sed 's/^.*load averages*: //; s/^.*load average: //'
    fi
    if [ "\(enabledChecks.contains("disk") ? "1" : "0")" = "1" ]; then df -P / | awk 'NR==2 {print "disk="$5}'; fi
    if [ "\(enabledChecks.contains("memory") ? "1" : "0")" = "1" ]; then
      if command -v free >/dev/null 2>&1; then free -m | awk '/^Mem:/ {printf "mem=%d%%\\n", ($3 * 100) / $2}'; else echo 'mem=n/a'; fi
    fi
    if [ "\(enabledChecks.contains("memory") ? "1" : "0")" = "1" ]; then
      free -b 2>/dev/null | awk '/^Swap:/ {printf "swap=%.2f GiB\\n", $3 / 1073741824}'
    fi
    if [ "\(enabledChecks.contains("disk") ? "1" : "0")" = "1" ]; then
      dev="$(findmnt -n -o MAJ:MIN / 2>/dev/null | awk '{print $1}')"
      statfile="/sys/dev/block/$dev/stat"
      if [ -n "$dev" ] && [ -r "$statfile" ]; then
        busy_a="$(awk '{print $10}' "$statfile")"
        time_a="$(awk '{print $1}' /proc/uptime)"
        sleep 1
        busy_b="$(awk '{print $10}' "$statfile")"
        time_b="$(awk '{print $1}' /proc/uptime)"
        awk -v a="$busy_a" -v b="$busy_b" -v ta="$time_a" -v tb="$time_b" 'BEGIN {if (tb > ta && b >= a) {v=(b-a)/(10*(tb-ta)); if(v>100)v=100; printf "disk_busy=%.0f%%\\n",v}}'
      fi
    fi
    if [ "\(services.isEmpty ? "0" : "1")" = "1" ] && command -v systemctl >/dev/null 2>&1; then
      hz="$(getconf CLK_TCK 2>/dev/null || echo 100)"
      cpus="$(nproc 2>/dev/null || echo 1)"
      read_ticks() {
        printf '%s\n' "$1" | while IFS= read -r pid; do
          awk '{sub(/^.*\\) /, ""); print $12 + $13}' "/proc/$pid/stat" 2>/dev/null
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
        # Cgroup CPU counters include workers that exit during the sample.
        # Fall back to process ticks only on systems without CPU accounting.
        read_cpu_usec() {
          if [ -n "$cgroup" ] && [ -r "/sys/fs/cgroup$cgroup/cpu.stat" ]; then
            awk '$1 == "usage_usec" {print $2}' "/sys/fs/cgroup$cgroup/cpu.stat"
          elif [ -n "$cgroup" ] && [ -r "/sys/fs/cgroup/cpuacct$cgroup/cpuacct.usage" ]; then
            awk '{printf "%.0f", $1/1000}' "/sys/fs/cgroup/cpuacct$cgroup/cpuacct.usage"
          else
            ticks="$(read_ticks "$pids")"
            awk -v ticks="$ticks" -v hz="$hz" 'BEGIN {printf "%.0f",ticks*1000000/hz}'
          fi
        }
        cpu_a="$(read_cpu_usec)"
        time_a="$(awk '{print $1}' /proc/uptime)"
        sleep 1
        cpu_b="$(read_cpu_usec)"
        time_b="$(awk '{print $1}' /proc/uptime)"
        stats="$(awk -v rss="$rss_kb" -v a="$cpu_a" -v b="$cpu_b" -v ta="$time_a" -v tb="$time_b" -v cpus="$cpus" 'BEGIN {
          if (cpus < 1) cpus = 1
          printf "%.2fGB ", rss / 1048576
          if (a == "" || b == "" || b < a || tb <= ta) printf "n/a"
          else printf "%.1f%%", (b-a)/1000000/(tb-ta)/cpus*100
        }')"
        printf '%s=%s %s\n' "$key" "$state" "$stats"
      }
      php_fpm_unit="$(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '$1 ~ /^php[0-9.]+-fpm\\.service$/ { sub(/\\.service$/, "", $1); print $1; exit }')"
      \(services)
    fi
    \(enabledChecks.contains("gpu") ? gpuCommand : "")
    """
    }

    /// NVIDIA tools are optional and run only for a server with `gpu` enabled.
    /// Prefix each record so the parser can distinguish inventories and samples.
    private static let gpuCommand = """
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi --query-gpu=index,uuid,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | sed 's/^/gpu_csv=/'
      gpu_processes="$(nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null)"
      echo "gpu_process_status=$?"
      printf '%s\\n' "$gpu_processes" | sed 's/^/gpu_process_csv=/'
      nvidia-smi pmon -c 1 -s um 2>/dev/null | sed 's/^/gpu_pmon=/'
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
        "memcached",
        "gpu"
    ]
}
