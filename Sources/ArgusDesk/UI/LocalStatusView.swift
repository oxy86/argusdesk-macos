import SwiftUI

/// Compact local Mac status block shown at the top of the overlay.
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
            MetricLine(leftLabel: "cpu", leftValue: status.cpu, rightLabel: "mem", rightValue: status.memory)
            MetricLine(leftLabel: "disk", leftValue: status.disk, rightLabel: "net", rightValue: status.network)
        }
    }
}
