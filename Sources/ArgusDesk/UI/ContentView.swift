import SwiftUI

/// Root SwiftUI view for the overlay.
///
/// The view is intentionally narrow and dense. It renders local Mac information
/// first, followed by remote server status, matching the agreed desktop
/// companion layout.
struct ContentView: View {
    /// Complete dashboard snapshot to render.
    let viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView(lastRefresh: viewModel.lastRefresh)
            LocalStatusView(status: viewModel.local)

            Divider()
                .overlay(Color.white.opacity(0.10))

            ServerListView(
                servers: viewModel.servers,
                refreshInterval: viewModel.remoteRefreshInterval
            )

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PanelBackground())
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.88))
    }
}

/// Small top row with the product name and last refresh time.
private struct HeaderView: View {
    /// Human-readable timestamp for the latest remote refresh.
    let lastRefresh: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("ArgusDesk")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

            Text(AppVersion.displayName)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))

            Spacer()

            Text(lastRefresh)
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }
}

/// Dark translucent panel material used behind the overlay content.
///
/// This custom drawing keeps the overlay look predictable from a
/// SwiftPM-launched executable.
private struct PanelBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.58))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }
}
