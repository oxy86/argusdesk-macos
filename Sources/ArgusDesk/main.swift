import SwiftUI

/// ArgusDesk app entry point.
///
/// Uses a standard SwiftUI @main with both a WindowGroup (for a real Dock
/// app window) and a MenuBarExtra (for the status icon and compact summary).
@main
struct ArgusDeskApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("ArgusDesk", id: "dashboard") {
            DashboardRootView(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            VStack {
                Button("Show ArgusDesk") {
                    openWindow(id: "dashboard")
                    NSApp.unhide(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Preferences") {
                    appDelegate.showPreferencesAction()
                }
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding()
            .frame(width: 200)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
        }
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
