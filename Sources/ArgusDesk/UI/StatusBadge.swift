import SwiftUI

/// Small textual status badge for a server's worst current state.
struct StatusBadge: View {
    /// Severity to display and colorize.
    let severity: Severity

    var body: some View {
        Text(severity.shortLabel)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(severity.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(severity.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Tiny colored indicator used before each server name.
struct StatusDot: View {
    /// Severity that controls the dot color.
    let severity: Severity

    var body: some View {
        Circle()
            .fill(severity.color)
            .frame(width: 6, height: 6)
    }
}
