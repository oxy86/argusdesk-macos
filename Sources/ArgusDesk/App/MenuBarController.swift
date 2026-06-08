import AppKit
import SwiftUI

/// Owns the macOS menu bar status item and compact summary menu.
///
/// It reads the current dashboard snapshot, shows the worst remote status in
/// the menu bar, and sends user commands back through small callbacks.
@MainActor
final class MenuBarController: NSObject {
    /// System-owned status item displayed in the menu bar.
    private let statusItem: NSStatusItem

    /// Latest dashboard snapshot used to rebuild the menu.
    private var dashboard: DashboardViewModel

    /// Whether a remote refresh is currently running.
    private var isRefreshing = false

    /// Called when the user chooses Refresh Now.
    private let refreshNow: () -> Void

    /// Called when the user chooses Show ArgusDesk.
    private let showOverlay: () -> Void

    /// Called when the user chooses Preferences.
    private let showPreferences: () -> Void

    /// Called when the user chooses Quit.
    private let quit: () -> Void

    /// Creates and immediately displays the menu bar item.
    init(
        dashboard: DashboardViewModel,
        refreshNow: @escaping () -> Void,
        showOverlay: @escaping () -> Void,
        showPreferences: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.dashboard = dashboard
        self.refreshNow = refreshNow
        self.showOverlay = showOverlay
        self.showPreferences = showPreferences
        self.quit = quit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        update(dashboard: dashboard, isRefreshing: false)
    }

    /// Updates the menu bar item and menu from the latest dashboard state.
    func update(dashboard: DashboardViewModel, isRefreshing: Bool) {
        self.dashboard = dashboard
        self.isRefreshing = isRefreshing
        updateButton()
        statusItem.menu = buildMenu()
    }

    /// Applies the compact colored status dot in the menu bar.
    private func updateButton() {
        guard let button = statusItem.button else {
            return
        }

        let severity = dashboard.overallSeverity
        button.attributedTitle = NSAttributedString(
            string: "●",
            attributes: [
                .foregroundColor: NSColor(severity.color),
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
            ]
        )
        button.toolTip = "ArgusDesk \(AppVersion.displayName): \(severity.rawValue)"
    }

    /// Builds the compact summary menu.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let counts = dashboard.severityCounts
        let problematicServers = dashboard.problematicServers

        menu.addItem(disabledItem("Overall: \(dashboard.overallSeverity.rawValue)"))
        menu.addItem(disabledItem("OK \(counts.ok)  WARN \(counts.warning)  ERR \(counts.error)"))
        menu.addItem(disabledItem("Last refresh: \(dashboard.lastRefresh)"))

        if !problematicServers.isEmpty {
            menu.addItem(.separator())
            for server in problematicServers.prefix(6) {
                menu.addItem(disabledItem("\(server.severity.shortLabel) \(server.name): \(server.headline)"))
            }
        }

        menu.addItem(.separator())
        let refreshItem = NSMenuItem(
            title: isRefreshing ? "Refreshing..." : "Refresh Now",
            action: #selector(refreshNowSelected),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = !isRefreshing
        menu.addItem(refreshItem)

        let showItem = NSMenuItem(
            title: "Show ArgusDesk",
            action: #selector(showOverlaySelected),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let preferencesItem = NSMenuItem(
            title: "Preferences",
            action: #selector(showPreferencesSelected),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitSelected), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    /// Convenience for menu rows that are labels, not commands.
    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Handles Refresh Now.
    @objc private func refreshNowSelected() {
        refreshNow()
    }

    /// Handles Show ArgusDesk.
    @objc private func showOverlaySelected() {
        showOverlay()
    }

    /// Handles Preferences.
    @objc private func showPreferencesSelected() {
        showPreferences()
    }

    /// Handles Quit.
    @objc private func quitSelected() {
        quit()
    }
}

/// Menu summary helpers derived from the dashboard snapshot.
private extension DashboardViewModel {
    /// Worst current remote server state.
    var overallSeverity: Severity {
        let engine = SeverityEngine()
        return engine.serverSeverity(for: servers.map { Metric(label: "server", value: $0.name, severity: $0.severity) })
    }

    /// Server counts by severity for the menu summary.
    var severityCounts: (ok: Int, warning: Int, error: Int) {
        (
            ok: servers.filter { $0.severity == .ok }.count,
            warning: servers.filter { $0.severity == .warning }.count,
            error: servers.filter { $0.severity == .error }.count
        )
    }

    /// Servers that need attention, with errors before warnings.
    var problematicServers: [ServerStatus] {
        servers
            .filter { $0.severity == .error || $0.severity == .warning }
            .sorted { left, right in
                left.severity.sortRank > right.severity.sortRank
            }
    }
}

/// Sort order for server attention lists.
private extension Severity {
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
