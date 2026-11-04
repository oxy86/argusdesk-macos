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

    /// Rows the user opened or closed by hand, keyed by server name.
    ///
    /// The name is used because `ServerStatus.id` changes on every refresh.
    @State private var overrides: [String: Bool] = [:]

    /// Current severity of each server, used to forget clicks after recovery.
    private var severities: [String: Severity] {
        Dictionary(servers.map { ($0.name, $0.severity) }, uniquingKeysWith: { first, _ in first })
    }

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
                        ServerStatusView(
                            server: server,
                            isExpanded: ServerExpansion.isExpanded(severity: server.severity, override: overrides[server.name])
                        ) { expanded in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                overrides[server.name] = expanded
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
        .onChange(of: severities) { _, newValue in
            overrides = ServerExpansion.pruned(overrides: overrides, severities: newValue)
        }
    }
}

/// Compact status group for one server.
///
/// The heading is always visible: connectivity dot, name, chips for anything
/// unhealthy, and the ping/HTTP summary. Clicking it shows or hides the metric
/// rows underneath, which provide dense operational detail without charts.
struct ServerStatusView: View {
    /// Server display model to render.
    let server: ServerStatus

    /// Whether the detail rows are shown.
    let isExpanded: Bool

    /// Called with the new open/closed state when the heading is clicked.
    let setExpanded: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .frame(width: 9)

                // The dot reports SSH connectivity; resource rows retain their
                // own health colors and overall health remains in the menu bar.
                StatusDot(severity: server.metrics.first { $0.label == "ssh" }?.severity ?? .unknown)
                    .help("SSH: \(server.metrics.first { $0.label == "ssh" }?.value ?? "unknown")")

                Text(server.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)

                let chips = server.chipSummary
                ForEach(chips.visible) { chip in
                    ChipView(text: chip.label, severity: chip.severity)
                }
                if chips.hidden > 0 {
                    ChipView(text: "+\(chips.hidden)", severity: chips.visible.first?.severity ?? .warning)
                }

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
            .contentShape(Rectangle())
            .onTapGesture {
                setExpanded(!isExpanded)
            }
            .help(isExpanded ? "Click to collapse" : "Click for details")

            if isExpanded {
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
        }
        .padding(.vertical, 4)
    }
}

/// Small coloured tag naming one unhealthy check on a collapsed server row.
private struct ChipView: View {
    /// Check name, or `+N` for chips that did not fit.
    let text: String

    /// Orange for a warning, red for an error.
    let severity: Severity

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(severity.color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(severity.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
