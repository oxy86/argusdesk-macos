import SwiftUI

/// ArgusDesk app entry point.
///
/// SwiftUI owns one dashboard window and one menu bar item.
@main
struct ArgusDeskApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // A Window scene reuses its dashboard when openWindow is called.
        // WindowGroup would create another dashboard on each Dock reopen.
        Window("ArgusDesk", id: "dashboard") {
            DashboardRootView(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            ArgusDeskMenu(snapshot: appDelegate.menuSnapshot, appDelegate: appDelegate) {
                openWindow(id: "dashboard")
                NSApp.unhide(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } label: {
            // Use the bundled artwork at its logical menu bar size.
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("ArgusDesk")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Observes the monitoring owner inside the view hierarchy. Each published
/// snapshot redraws the dashboard rather than retaining the launch snapshot.
private struct DashboardRootView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appDelegate: AppDelegate
    /// Shared with Preferences so changing the arrangement resizes the window.
    @AppStorage("serverLayout") private var layout: ServerLayout = .vertical

    var body: some View {
        ContentView(
            viewModel: appDelegate.dashboardViewModel,
            showPreferences: { appDelegate.showPreferencesAction() }
        )
        .onAppear { appDelegate.openDashboard = { openWindow(id: "dashboard") } }
        .frame(width: layout.contentSize(servers: appDelegate.dashboardViewModel.servers).width,
               height: layout.contentSize(servers: appDelegate.dashboardViewModel.servers).height)
    }
}
