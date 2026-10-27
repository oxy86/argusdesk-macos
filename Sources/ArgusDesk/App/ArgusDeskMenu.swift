import SwiftUI

/// A read-only projection of the dashboard's completed server results.
/// No timer or monitoring service belongs to the menu. Local Mac samples and
/// refresh-start notifications do not republish this projection.
@MainActor
final class MenuSnapshot: ObservableObject {
    @Published private(set) var dashboard = DashboardViewModel.empty

    func update(from snapshot: DashboardViewModel) {
        guard snapshot.servers.map(\.id) != dashboard.servers.map(\.id)
            || snapshot.lastRefresh != dashboard.lastRefresh
            || snapshot.remoteRefreshInterval != dashboard.remoteRefreshInterval else { return }
        dashboard = snapshot
    }
}

/// Observes only server results, keeping the open menu stable between results.
struct ArgusDeskMenu: View {
    @ObservedObject var snapshot: MenuSnapshot
    let appDelegate: AppDelegate
    let showDashboard: () -> Void

    var body: some View {
        let dashboard = snapshot.dashboard
        let counts = dashboard.severityCounts
        Text("Overall: \(dashboard.overallSeverity.rawValue)")
            .foregroundStyle(.primary)
        Text("OK \(counts.ok)  WARN \(counts.warning)  ERR \(counts.error)  UNKNOWN \(dashboard.servers.filter { $0.severity == .unknown }.count)")
        Text("Last server result: \(dashboard.lastRefresh)")
        Divider()
        if dashboard.servers.isEmpty {
            Text("No servers configured")
        }
        ForEach(Array(dashboard.menuServers.enumerated()), id: \.offset) { _, server in
            Menu {
                Text("Status: \(server.severity.rawValue)")
                if let resultAt = server.lastResultAt {
                    Text("Last result: \(resultAt.formatted(date: .omitted, time: .standard))")
                } else {
                    Text("Waiting for first result")
                }
                if let interval = server.refreshInterval {
                    Text("Refresh interval: \(interval)")
                }
                Divider()
                ForEach(server.menuMetrics) { metric in
                    Label("\(metric.label): \(metric.value)", systemImage: metric.severity.menuSymbol)
                }
                if server.menuMetrics.isEmpty {
                    Text("No checks enabled")
                }
                Divider()
                Button("Open Dashboard", action: showDashboard)
            } label: {
                Label("\(server.name) — \(server.severity.rawValue)", systemImage: server.severity.menuSymbol)
            }
        }
        Divider()
        Button("Refresh Now") {
            appDelegate.refreshNow()
        }
        .keyboardShortcut("r")
        Button("Show ArgusDesk", action: showDashboard)
        Button("Preferences") { appDelegate.showPreferencesAction() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

}

/// Menu summary helpers derived from the dashboard snapshot.
extension DashboardViewModel {
    /// Worst current remote server state.
    var overallSeverity: Severity {
        if servers.contains(where: { $0.severity == .error }) { return .error }
        if servers.contains(where: { $0.severity == .warning }) { return .warning }
        // An unchecked server must not make an incomplete fleet look healthy.
        if servers.isEmpty || servers.contains(where: { $0.severity == .unknown }) { return .unknown }
        return .ok
    }

    /// Server counts by severity for the menu summary.
    var severityCounts: (ok: Int, warning: Int, error: Int) {
        (
            ok: servers.filter { $0.severity == .ok }.count,
            warning: servers.filter { $0.severity == .warning }.count,
            error: servers.filter { $0.severity == .error }.count
        )
    }

    /// Show every server, preserving configuration order within each severity.
    var menuServers: [ServerStatus] {
        servers.enumerated()
            .sorted { left, right in
                left.element.severity.sortRank == right.element.severity.sortRank
                    ? left.offset < right.offset
                    : left.element.severity.sortRank > right.element.severity.sortRank
            }.map(\.element)
    }
}

/// Sort order for server attention lists.
extension Severity {
    /// Native symbols make state readable without relying on color.
    var menuSymbol: String {
        switch self {
        case .ok: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        case .unknown: "questionmark.circle"
        }
    }

    /// Higher values should appear first in the menu.
    var sortRank: Int {
        switch self {
        case .error:
            4
        case .warning:
            3
        case .unknown:
            2
        case .ok:
            1
        }
    }
}

/// Hide disabled checks while retaining unknown and failed readings as reported.
extension ServerStatus {
    var menuMetrics: [Metric] {
        metrics.filter { $0.value != "off" }
    }
}
