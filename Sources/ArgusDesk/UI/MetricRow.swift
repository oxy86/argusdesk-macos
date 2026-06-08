import SwiftUI

/// One compact metric row inside a server status block.
///
/// The fixed label width keeps rows aligned and readable in the narrow overlay.
struct MetricRow: View {
    /// Metric display model to render.
    let metric: Metric

    var body: some View {
        HStack(spacing: 8) {
            Text(metric.label)
                .foregroundStyle(Color.white.opacity(0.48))
                .frame(width: 52, alignment: .leading)

            Text(metric.value)
                .foregroundStyle(metric.severity == .unknown ? Color.white.opacity(0.42) : metric.severity.color)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
    }
}

/// Two-column local metric row used by the local Mac section.
///
/// This keeps local data dense while preserving enough spacing for scanability.
struct MetricLine: View {
    /// Label for the left metric.
    let leftLabel: String

    /// Value for the left metric.
    let leftValue: String

    /// Label for the right metric.
    let rightLabel: String

    /// Value for the right metric.
    let rightValue: String

    var body: some View {
        HStack(spacing: 8) {
            Text(leftLabel)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(leftValue)
                .foregroundStyle(Color.white.opacity(0.82))

            Spacer(minLength: 8)

            Text(rightLabel)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(rightValue)
                .lineLimit(1)
                .foregroundStyle(Color.white.opacity(0.82))
        }
        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
    }
}

/// Small uppercase label used to introduce compact sections.
struct SectionHeader: View {
    /// Section title text.
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.42))
    }
}
