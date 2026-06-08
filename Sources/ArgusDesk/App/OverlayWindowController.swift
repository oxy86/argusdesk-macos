import AppKit
import SwiftUI

/// Owns the desktop overlay window and embeds the SwiftUI dashboard view.
///
/// This controller focuses on window behavior and view replacement:
/// transparent borderless panel, right-side placement, all-Spaces visibility,
/// non-focus-stealing presentation, and lightweight dashboard updates.
@MainActor
final class OverlayWindowController {
    /// The underlying AppKit panel.
    ///
    /// `NSPanel` is used instead of a standard `NSWindow` because it supports
    /// non-activating behavior, which is closer to a desktop widget.
    private let panel: NSPanel

    /// Dashboard data rendered by the hosted SwiftUI view.
    private var viewModel: DashboardViewModel

    /// Hosted SwiftUI root view.
    ///
    /// AppKit owns the window while SwiftUI owns the layout. Keeping the hosting
    /// view lets the app replace the root value model as local stats refresh.
    private var hostingView: NSHostingView<ContentView>?

    /// Creates the overlay window at a sensible default size and position.
    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel

        let size = NSSize(width: 286, height: 760)
        let frame = Self.defaultFrame(size: size)

        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
    }

    /// Displays the panel without activating the app.
    func show() {
        panel.orderFrontRegardless()
    }

    /// Replaces the rendered dashboard snapshot.
    func update(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        hostingView?.rootView = ContentView(viewModel: viewModel)
    }

    /// Applies overlay window styling and embeds the SwiftUI view tree.
    private func configurePanel() {
        panel.title = "ArgusDesk"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

        let rootView = ContentView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        self.hostingView = hostingView
        panel.contentView = hostingView
    }

    /// Calculates the initial right-side overlay frame for the current screen.
    ///
    /// The frame uses the visible screen area so it avoids the menu bar and Dock
    /// when possible. Position and size persistence are tracked in the roadmap.
    private static func defaultFrame(size: NSSize) -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 14
        let height = min(size.height, screenFrame.height - (margin * 2))
        let originX = screenFrame.maxX - size.width - margin
        let originY = screenFrame.maxY - height - margin

        return NSRect(
            x: originX,
            y: originY,
            width: size.width,
            height: height
        )
    }
}
