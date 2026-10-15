import SwiftUI

/// Saved arrangement. Sizes account for enabled metrics and GPU process rows.
enum ServerLayout: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }
    var title: String { self == .vertical ? "Vertical" : "Horizontal" }
    func contentSize(servers: [ServerStatus]) -> CGSize {
        let heights = servers.map { server in
            // GPU process descriptions can wrap onto two lines. Secondary disk
            // and memory readings are incorporated into their resource rows.
            let metrics = server.visibleMetrics.filter { !["disk busy", "swap"].contains($0.label) }
            let rows = metrics.count
            let processRows = metrics.filter { $0.label.hasPrefix("pid ") }.count
            return CGFloat(44 + rows * 16 + processRows * 13)
        }
        if self == .vertical {
            return CGSize(width: 380, height: max(820, 200 + heights.reduce(0, +) + CGFloat(max(0, servers.count - 1) * 12)))
        }
        let count = max(1, servers.count)
        return CGSize(width: CGFloat(360 * count + 18 * (count - 1) + 24), height: max(420, 190 + (heights.max() ?? 0)))
    }
}
