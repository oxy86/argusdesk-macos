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

    /// The menu bar icon loaded from bundle resources, marked as template.
    private var menuBarIcon: NSImage?

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

        // Create a global status item for the menu bar.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.title = "●"
        statusItem.toolTip = "ArgusDesk"

        super.init()

        // Load the template menu bar icon from bundle resources.
        // Tries multiple lookup strategies since SwiftPM executables
        // don't always resolve Bundle.main correctly.
        loadMenuBarIcon()

        // Schedule menu setup after the run loop stabilizes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateButton()
            self?.statusItem.menu = self?.buildMenu()
        }
    }

    /// Updates the menu bar item and menu from the latest dashboard state.
    func update(dashboard: DashboardViewModel, isRefreshing: Bool) {
        self.dashboard = dashboard
        self.isRefreshing = isRefreshing
        updateButton()
        statusItem.menu = buildMenu()
    }

    /// Applies the menu bar icon to the status item button.
    ///
    /// The icon is loaded as a template image (`isTemplate = true`), so macOS
    /// automatically tints it for light/dark mode and hover state.
    private func updateButton() {
        guard let button = statusItem.button else {
            return
        }

        // If we have a custom icon from Resources, use it.
        if let icon = menuBarIcon {
            button.image = icon
            button.toolTip = "ArgusDesk: \(dashboard.overallSeverity.rawValue)"
            return
        }

        // Fallback: colored severity dot.
        let severity = dashboard.overallSeverity
        let color = NSColor(severity.color)
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { bounds in
            let ctx = NSGraphicsContext.current!
            ctx.saveGraphicsState()
            NSColor.black.setFill()
            let _ = NSBezierPath.fill(NSBezierPath(ovalIn: bounds))
            color.setFill()
            let _ = NSBezierPath.fill(NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3)))
            ctx.restoreGraphicsState()
            return true
        }
        image.isTemplate = false
        button.image = image
        button.toolTip = "ArgusDesk: \(severity.rawValue)"
    }

    /// Loads the menu bar icon from bundle resources if available.
    ///
    /// Tries `menubar-icon@2x.png` (44×44) first, then `menubar-icon.png`
    /// (22×22). Sets `isTemplate = true` so macOS handles light/dark/hover
    /// tinting automatically. If the icon is not found, the menu bar stays
    /// with the default title fallback.
    private func loadMenuBarIcon() {
        // Strategy 1: standard Bundle.main lookup (works for proper .app bundles).
        var url: URL?
        url = Bundle.main.url(
            forResource: "menubar-icon@2x",
            withExtension: "png"
        ) ?? Bundle.main.url(
            forResource: "menubar-icon",
            withExtension: "png"
        )

        // Strategy 2: look next to the executable (works for SwiftPM builds).
        if url == nil {
            let execDir = Bundle.main.bundleURL.deletingLastPathComponent()
            url = execDir.appendingPathComponent("menubar-icon.png")
            if !FileManager.default.fileExists(atPath: url!.path) {
                url = execDir.appendingPathComponent("menubar-icon@2x.png")
            }
        }

        // Strategy 3: look in Resources relative to bundle path.
        if url == nil {
            let resourcesURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
            url = resourcesURL.appendingPathComponent("menubar-icon.png")
            if !FileManager.default.fileExists(atPath: url!.path) {
                url = resourcesURL.appendingPathComponent("menubar-icon@2x.png")
            }
        }

        guard let url else {
            return
        }

        guard let image = NSImage(contentsOf: url) else {
            return
        }

        image.isTemplate = true
        menuBarIcon = image
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
        menu.addItem(NSMenuItem(
            title: isRefreshing ? "Refreshing..." : "Refresh Now",
            action: #selector(refreshNowSelected),
            keyEquivalent: "r"
        ))

        menu.addItem(NSMenuItem(
            title: "Show ArgusDesk",
            action: #selector(showOverlaySelected),
            keyEquivalent: ""
        ))

        menu.addItem(NSMenuItem(
            title: "Preferences",
            action: #selector(showPreferencesSelected),
            keyEquivalent: ","
        ))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitSelected), keyEquivalent: "q"))

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
        let engine = SeverityEngine(thresholds: .default)
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
