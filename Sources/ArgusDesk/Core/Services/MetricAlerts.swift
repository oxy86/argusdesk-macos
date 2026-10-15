import Foundation

/// A native notification's presentation text, independent of macOS delivery.
struct MetricAlert {
    let identifier: String
    let server: String
    let title: String
    let body: String
}

/// Tracks each metric separately so one existing server fault cannot mask a
/// second threshold crossing. Unknown readings preserve the previous state.
struct MetricAlerts {
    private var previous: [String: Severity] = [:]

    mutating func evaluate(servers: [ServerStatus], thresholds: Thresholds, recovery: Bool) -> [MetricAlert] {
        var alerts: [MetricAlert] = []
        let names = Set(servers.map(\.name))
        previous = previous.filter { names.contains(String($0.key.split(separator: "\u{1f}").first ?? "")) }
        for server in servers {
            for metric in server.metrics {
                let key = server.name + "\u{1f}" + metric.label
                if metric.value == "off" { previous.removeValue(forKey: key); continue }
                guard metric.severity != .unknown else { continue }
                let old = previous[key]
                previous[key] = metric.severity
                guard old != metric.severity else { continue }
                let isRecovery = metric.severity == .ok && (old == .warning || old == .error)
                guard metric.severity == .warning || metric.severity == .error || (isRecovery && recovery) else { continue }
                let label = metric.label == "mem" ? "Memory" : metric.label == "disk /" ? "Disk" : metric.label.capitalized
                let state = isRecovery ? "recovered" : metric.severity == .warning ? "warning" : "critical"
                var body = "\(label): \(metric.value)."
                if !isRecovery, let limit = limit(for: metric, thresholds: thresholds) {
                    body += " \(metric.severity == .warning ? "Warning" : "Critical") threshold: \(limit)."
                }
                alerts.append(MetricAlert(identifier: key, server: server.name,
                    title: "\(server.name) — \(label) \(state)", body: body))
            }
        }
        return alerts
    }

    private func limit(for metric: Metric, thresholds: Thresholds) -> String? {
        let error = metric.severity == .error
        switch metric.label {
        case "disk /", "mem": return "\(Int(error ? thresholds.usageErrorPercent : thresholds.usageWarningPercent))%"
        case "ping":
            guard metric.value.first?.isNumber == true else { return nil }
            return "\(Int(error ? thresholds.pingErrorMilliseconds : thresholds.pingWarningMilliseconds)) ms"
        case "nginx", "db", "php-fpm", "memcached":
            guard metric.value.hasPrefix("active ") else { return nil }
            let warning = metric.label == "php-fpm" ? thresholds.phpFPMCPUWarningPercent : thresholds.serviceCPUWarningPercent
            let critical = metric.label == "php-fpm" ? thresholds.phpFPMCPUErrorPercent : thresholds.serviceCPUErrorPercent
            return "\(Int(error ? critical : warning))% CPU"
        default:
            var limits: [String] = []
            let utilizationLimit = error ? thresholds.gpuErrorPercent : thresholds.gpuWarningPercent
            let memoryLimit = error ? thresholds.gpuMemoryErrorPercent : thresholds.gpuMemoryWarningPercent
            if let value = metric.gpuUtilizationPercent, value >= utilizationLimit { limits.append("\(Int(utilizationLimit))% GPU utilization") }
            if let value = metric.gpuMemoryUsagePercent, value >= memoryLimit { limits.append("\(Int(memoryLimit))% VRAM") }
            return limits.isEmpty ? nil : limits.joined(separator: "; ")
        }
    }
}
