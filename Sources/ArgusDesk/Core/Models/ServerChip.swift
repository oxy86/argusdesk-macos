import Foundation

/// A small coloured tag shown on a collapsed server row for one unhealthy check.
struct ServerChip: Equatable, Identifiable {
    /// Short check name, such as `php-fpm` or `disk`.
    let label: String

    /// `warning` (orange) or `error` (red).
    let severity: Severity

    var id: String { label }
}

extension ServerStatus {
    /// Most chips drawn on one row before the rest are summarised as `+N`.
    static let maxVisibleChips = 3

    /// Every unhealthy check, with errors first and then warnings.
    ///
    /// Only body checks become chips. Ping and HTTP stay in the row heading and
    /// already show their own colour. When SSH itself fails, the other readings
    /// are meaningless, so a single `unreachable` chip replaces them.
    var chips: [ServerChip] {
        if metrics.first(where: { $0.label == "ssh" })?.severity == .error {
            return [ServerChip(label: "unreachable", severity: .error)]
        }

        var seen = Set<String>()
        let unhealthy: [ServerChip] = visibleMetrics.compactMap { metric in
            guard metric.severity == .warning || metric.severity == .error else {
                return nil
            }

            // "disk /" is shown as plain "disk"; other labels are already short.
            let label = metric.label == "disk /" ? "disk" : metric.label
            return seen.insert(label).inserted ? ServerChip(label: label, severity: metric.severity) : nil
        }

        return unhealthy.filter { $0.severity == .error } + unhealthy.filter { $0.severity == .warning }
    }

    /// The chips that fit on the row, and how many more were left out.
    var chipSummary: (visible: [ServerChip], hidden: Int) {
        let all = chips
        return (Array(all.prefix(Self.maxVisibleChips)), max(0, all.count - Self.maxVisibleChips))
    }
}

/// Rules for which server rows are open.
///
/// A row opens by itself when its server has a warning or error. A click
/// overrides that choice until the server becomes healthy again, so a row you
/// closed stays closed until the next time something goes wrong.
enum ServerExpansion {
    /// Whether the row is open, given the user's click (if any).
    static func isExpanded(severity: Severity, override: Bool?) -> Bool {
        override ?? (severity == .warning || severity == .error)
    }

    /// Drops overrides for servers that are healthy (or gone) so the next
    /// problem opens them automatically again.
    static func pruned(overrides: [String: Bool], severities: [String: Severity]) -> [String: Bool] {
        overrides.filter { name, _ in
            guard let severity = severities[name] else {
                return false
            }

            return severity == .warning || severity == .error
        }
    }
}
