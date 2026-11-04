import SwiftUI

/// Compact local Mac status block shown at the top of the window.
///
/// Local stats are secondary to remote server health, but they stay at the top
/// because they provide useful context about the machine running ArgusDesk.
///
/// Collapsed, the block is a "LOCAL" heading plus two lines:
/// addresses with the OS version, then the main utilization figures. Clicking
/// the heading or either line opens the remaining details.
struct LocalStatusView: View {
    /// Local status values to render.
    let status: LocalStatus

    /// Whether the extra detail rows are shown. Starts collapsed.
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // The heading and the two summary lines act as one click target.
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .frame(width: 9)
                    SectionHeader(title: "LOCAL")
                    Spacer(minLength: 0)
                }

                // Line 1: internal and external address, then the macOS version.
                Text(status.addressSummary)
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Line 2: utilization. Only the 1-minute load fits here.
                HStack(spacing: 12) {
                    SummaryValue(label: "cpu", value: status.cpu)
                    SummaryValue(label: "gpu", value: status.gpu)
                    SummaryValue(label: "load", value: status.shortLoad)
                    SummaryValue(label: "mem", value: status.memory)
                    SummaryValue(label: "disk", value: status.disk)
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
            .contentShape(Rectangle())
            .onTapGesture {
                isExpanded.toggle()
            }
            .help(isExpanded ? "Click to collapse" : "Click for more details")

            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(status.hostname)
                            .foregroundStyle(Color.white.opacity(0.92))
                        Spacer()
                        Text("up \(status.uptime)")
                            .foregroundStyle(Color.white.opacity(0.58))
                    }

                    MetricLine(leftLabel: "load", leftValue: status.loadAverage, rightLabel: "bat", rightValue: status.battery)
                    MetricLine(leftLabel: "net", leftValue: status.network, rightLabel: "", rightValue: "")
                    ResourceRow(label: "disk", usage: Metric(label: "disk", value: status.disk, severity: .ok), secondary: Metric(label: "busy", value: status.diskBusy, severity: .unknown), suffix: "busy")
                    ResourceRow(label: "mem", usage: Metric(label: "mem", value: status.memory, severity: .ok), secondary: Metric(label: "swap", value: status.swap, severity: .unknown), suffix: "swap")
                }
                .padding(.leading, 14)
            }
        }
    }
}

/// A dimmed label followed by its value, used in the collapsed LOCAL summary.
private struct SummaryValue: View {
    /// Short name, such as `cpu`.
    let label: String

    /// Formatted reading, such as `12%`.
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(value)
                .foregroundStyle(Color.white.opacity(0.82))
        }
    }
}
