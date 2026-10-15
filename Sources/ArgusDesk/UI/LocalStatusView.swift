import SwiftUI

/// Compact local Mac status block shown at the top of the window.
///
/// Local stats are secondary to remote server health, but they stay at the top
/// because they provide useful context about the machine running ArgusDesk.
struct LocalStatusView: View {
    /// Local status values to render.
    let status: LocalStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionHeader(title: "LOCAL")

            HStack {
                Text(status.hostname)
                    .foregroundStyle(Color.white.opacity(0.92))
                Spacer()
                Text(status.osVersion)
                    .foregroundStyle(Color.white.opacity(0.58))
            }

            MetricLine(leftLabel: "up", leftValue: status.uptime, rightLabel: "bat", rightValue: status.battery)
            MetricLine(leftLabel: "cpu", leftValue: status.cpu, rightLabel: "net", rightValue: status.network)
            ResourceRow(label: "disk", usage: Metric(label: "disk", value: status.disk, severity: .ok), secondary: Metric(label: "busy", value: status.diskBusy, severity: .unknown), suffix: "busy")
            ResourceRow(label: "mem", usage: Metric(label: "mem", value: status.memory, severity: .ok), secondary: Metric(label: "swap", value: status.swap, severity: .unknown), suffix: "swap")
        }
    }
}
