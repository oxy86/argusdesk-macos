import SwiftUI

/// Saved arrangement. Sizes account for enabled metrics and GPU process rows.
enum ServerLayout: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }
    var title: String { self == .vertical ? "Vertical" : "Horizontal" }

    /// Height limits for the user-selected window height, in points.
    static let windowHeightRange = 400...1600

    /// Default window height, in points. Matches the previous minimum height.
    static let defaultWindowHeight = 820

    /// Window content size for this arrangement.
    ///
    /// The width follows the arrangement (one column, or one column per
    /// server). The height is chosen by the user in Preferences and never grows
    /// with the number of servers; the dashboard scrolls when its content is
    /// taller than the window instead.
    func contentSize(servers: [ServerStatus], windowHeight: Int = ServerLayout.defaultWindowHeight) -> CGSize {
        let height = CGFloat(min(max(windowHeight, Self.windowHeightRange.lowerBound), Self.windowHeightRange.upperBound))
        if self == .vertical {
            return CGSize(width: 380, height: height)
        }
        let count = max(1, servers.count)
        return CGSize(width: CGFloat(360 * count + 18 * (count - 1) + 24), height: height)
    }
}
