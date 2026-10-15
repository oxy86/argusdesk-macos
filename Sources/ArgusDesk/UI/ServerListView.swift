import SwiftUI

/// Renders the remote server section of the overlay.
///
/// This is the primary content area for ArgusDesk and renders the latest remote
/// monitoring results.
struct ServerListView: View {
    /// Uses the same saved arrangement as the window and Preferences.
    @AppStorage("serverLayout") private var layout: ServerLayout = .vertical
    /// Server rows to display.
    let servers: [ServerStatus]

    /// Human-readable refresh interval label.
    let refreshInterval: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "SERVERS")
                Spacer()
                Text("global \(refreshInterval)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.48))
            }

            if servers.isEmpty {
                Text("No servers configured")
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .padding(.vertical, 4)
            } else {
                // AnyLayout preserves card identity when the arrangement changes.
                let cards = layout == .vertical
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 18))
                cards {
                    ForEach(servers) { server in
                        ServerStatusView(server: server)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
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
                // The dot reports SSH connectivity; resource rows retain their
                // own health colors and overall health remains in the menu bar.
                StatusDot(severity: server.metrics.first { $0.label == "ssh" }?.severity ?? .unknown)
                    .help("SSH: \(server.metrics.first { $0.label == "ssh" }?.value ?? "unknown")")

                Text(server.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))

                Spacer(minLength: 8)

                if let ping = server.metrics.first(where: { $0.label == "ping" }) {
                    Text(ping.value)
                        .foregroundStyle(ping.severity.color)
                        .lineLimit(1)
                }
                if let http = server.metrics.first(where: { $0.label == "http" }), http.value != "off" {
                    Text("HTTP \(http.value)")
                        .foregroundStyle(http.severity.color)
                        .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                if let load = server.visibleMetrics.first(where: { $0.label == "load" }) {
                    MetricRow(metric: load)
                }
                if let disk = server.visibleMetrics.first(where: { $0.label == "disk /" }) {
                    ResourceRow(label: "disk", usage: disk, secondary: server.metrics.first { $0.label == "disk busy" }, suffix: "busy")
                }
                if let memory = server.visibleMetrics.first(where: { $0.label == "mem" }) {
                    ResourceRow(label: "mem", usage: memory, secondary: server.metrics.first { $0.label == "swap" }, suffix: "swap")
                }
                ForEach(server.visibleMetrics.filter { !["load", "disk /", "mem", "disk busy", "swap"].contains($0.label) }) { metric in
                    MetricRow(metric: metric)
                        .help("\(metric.label): \(metric.value)")
                }
            }
            .padding(.leading, 14)
            if let interval = server.refreshInterval {
                Text("refresh \(interval)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .padding(.leading, 14)
            }
        }
        .padding(.vertical, 4)
    }
}
