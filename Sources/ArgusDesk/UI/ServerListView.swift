import SwiftUI

/// Renders the remote server section of the overlay.
///
/// This is the primary content area for ArgusDesk and renders the latest remote
/// monitoring results.
struct ServerListView: View {
    /// Server rows to display.
    let servers: [ServerStatus]

    /// Human-readable refresh interval label.
    let refreshInterval: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "SERVERS")
                Spacer()
                Text("refresh \(refreshInterval)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.48))
            }

            if servers.isEmpty {
                Text("No servers configured")
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .padding(.vertical, 4)
            } else {
                ForEach(servers) { server in
                    ServerStatusView(server: server)
                }
            }
        }
    }
}

/// Compact status group for one server.
///
/// The header surfaces the worst server state and the most important summary.
/// The metric rows underneath provide dense operational detail without charts.
struct ServerStatusView: View {
    /// Server display model to render.
    let server: ServerStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                StatusDot(severity: server.severity)

                Text(server.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))

                Spacer(minLength: 8)

                Text(server.headline)
                    .lineLimit(1)
                    .foregroundStyle(Color.white.opacity(0.58))

                StatusBadge(severity: server.severity)
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(server.metrics) { metric in
                    MetricRow(metric: metric)
                }
            }
            .padding(.leading, 14)
        }
        .padding(.vertical, 4)
    }
}
