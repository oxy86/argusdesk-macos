import Foundation

/// Applies ArgusDesk severity rules to check metrics.
///
/// Centralized escalation lets monitoring code focus on collecting values.
/// Thresholds are configurable and passed in from user preferences.
struct SeverityEngine {
    /// Ping latency above this value is degraded but reachable.
    let pingWarningMilliseconds: Double

    /// Ping latency above this value is treated as effectively unusable.
    let pingErrorMilliseconds: Double

    /// Disk or memory usage at or above this value is degraded.
    let usageWarningPercent: Double

    /// Disk or memory usage at or above this value is critical.
    let usageErrorPercent: Double

    /// Service CPU normalized to total system capacity at or above this
    /// value is degraded.
    let serviceCPUWarningPercent: Double

    /// Service CPU normalized to total system capacity at or above this
    /// value is critical.
    let serviceCPUErrorPercent: Double

    /// Creates an engine with the user-specified thresholds.
    init(thresholds: Thresholds) {
        self.pingWarningMilliseconds = thresholds.pingWarningMilliseconds
        self.pingErrorMilliseconds = thresholds.pingErrorMilliseconds
        self.usageWarningPercent = thresholds.usageWarningPercent
        self.usageErrorPercent = thresholds.usageErrorPercent
        self.serviceCPUWarningPercent = thresholds.serviceCPUWarningPercent
        self.serviceCPUErrorPercent = thresholds.serviceCPUErrorPercent
    }

    /// Returns metrics with recalculated severities.
    func evaluate(metrics: [Metric]) -> [Metric] {
        metrics.map { metric in
            Metric(
                label: metric.label,
                value: metric.value,
                severity: severity(for: metric)
            )
        }
    }

    /// Returns the server-level worst severity using escalation rules.
    func serverSeverity(for metrics: [Metric]) -> Severity {
        if metrics.contains(where: { $0.severity == .error }) {
            return .error
        }

        if metrics.contains(where: { $0.severity == .warning }) {
            return .warning
        }

        if metrics.contains(where: { $0.severity == .ok }) {
            return .ok
        }

        return .unknown
    }

    /// Computes the best severity for one metric label/value pair.
    private func severity(for metric: Metric) -> Severity {
        switch metric.label {
        case "ssh":
            metric.value == "off" ? .unknown : (metric.value == "ok" ? .ok : .error)
        case "ping":
            pingSeverity(metric.value)
        case "http":
            httpSeverity(metric.value)
        case "disk /", "mem":
            percentSeverity(metric.value)
        case "nginx", "db", "php-fpm", "memcached":
            serviceSeverity(metric.value)
        case "load":
            metric.value == "n/a" || metric.value == "-" ? .unknown : .ok
        default:
            metric.severity
        }
    }

    /// Severity for ping latency strings such as `18.2ms`.
    private func pingSeverity(_ value: String) -> Severity {
        if value == "timeout" || value == "fail" {
            return .error
        }

        guard let milliseconds = firstNumber(in: value) else {
            return value == "ok" ? .ok : .unknown
        }

        if milliseconds >= pingErrorMilliseconds {
            return .error
        }

        if milliseconds >= pingWarningMilliseconds {
            return .warning
        }

        return .ok
    }

    /// Severity for HTTP status code strings.
    private func httpSeverity(_ value: String) -> Severity {
        if value == "n/a" {
            return .unknown
        }

        if value == "timeout" || value == "fail" {
            return .error
        }

        guard let statusCode = Int(value) else {
            return .unknown
        }

        if statusCode == 200 {
            return .ok
        }

        if (300..<500).contains(statusCode) {
            return .warning
        }

        return .error
    }

    /// Severity for percentage strings such as `84%`.
    private func percentSeverity(_ value: String) -> Severity {
        guard let percent = firstNumber(in: value) else {
            return .unknown
        }

        if percent >= usageErrorPercent {
            return .error
        }

        if percent >= usageWarningPercent {
            return .warning
        }

        return .ok
    }

    /// Severity for service strings such as `active 0.12GB 1.4%`.
    private func serviceSeverity(_ value: String) -> Severity {
        if value == "off" || value == "n/a" {
            return .unknown
        }

        let parts = value.split(separator: " ")
        guard let state = parts.first else {
            return .unknown
        }

        guard state == "active" else {
            return .error
        }

        guard let cpuPercent = percentNumbers(in: value).last else {
            return .ok
        }

        if cpuPercent >= serviceCPUErrorPercent {
            return .error
        }

        if cpuPercent >= serviceCPUWarningPercent {
            return .warning
        }

        return .ok
    }

    /// First decimal number in a metric value.
    private func firstNumber(in value: String) -> Double? {
        numberScanner(in: value).first
    }

    /// All decimal numbers that are followed by a percent sign.
    private func percentNumbers(in value: String) -> [Double] {
        value
            .split(separator: " ")
            .filter { $0.hasSuffix("%") }
            .compactMap { firstNumber(in: String($0)) }
    }

    /// Parses positive decimal numbers from a compact metric string.
    private func numberScanner(in value: String) -> [Double] {
        let allowedCharacters = CharacterSet(charactersIn: "0123456789.")
        let pieces = value.components(separatedBy: allowedCharacters.inverted)
        return pieces.compactMap { piece in
            guard !piece.isEmpty else {
                return nil
            }

            return Double(piece)
        }
    }
}
