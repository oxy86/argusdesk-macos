import SwiftUI

/// Root SwiftUI view for the main window.
///
/// The view is intentionally narrow and dense. It renders local Mac information
/// first, followed by remote server status, matching the agreed desktop
/// companion layout. The header stays pinned and the rest scrolls when needed.
struct ContentView: View {
    /// Complete dashboard snapshot to render.
    let viewModel: DashboardViewModel

    /// User action to open the Preferences window.
    let showPreferences: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView(
                lastRefresh: viewModel.lastRefresh,
                showPreferences: showPreferences
            )

            // Everything below the pinned header scrolls. The scroll bar only
            // appears when the content is taller than the window.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    if let validation = viewModel.configValidation,
                       validation.hasProblems {
                        ConfigValidationView(validation: validation)
                        Divider()
                            .overlay(Color.white.opacity(0.10))
                    }

                    LocalStatusView(status: viewModel.local)

                    Divider()
                        .overlay(Color.white.opacity(0.10))

                    ServerListView(
                        servers: viewModel.servers,
                        refreshInterval: viewModel.remoteRefreshInterval
                    )
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(DarkScrollerStyle())
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PanelBackground())
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.88))
    }
}

/// Small top row with the product name, last refresh time, and Preferences button.
private struct HeaderView: View {
    /// Human-readable timestamp for the latest remote refresh.
    let lastRefresh: String

    /// User action to open the Preferences window.
    let showPreferences: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("ArgusDesk")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

            Text(AppVersion.displayName)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))

            Spacer()

            Button(action: showPreferences) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.50))
            }
            .buttonStyle(.plain)
            .help("Open Preferences")

            Text(lastRefresh)
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }
}

/// Displays configuration validation errors and warnings.
///
/// Errors (red) indicate problems that will prevent checks from running.
/// Warnings (amber) flag potential issues that are not critical.
private struct ConfigValidationView: View {
    /// Validation problems discovered during config loading.
    let validation: ConfigValidation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CONFIGURATION")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))

            ForEach(validation.allMessages, id: \.self) { message in
                let isError = validation.errors.contains(message)
                HStack(spacing: 6) {
                    Text(isError ? "✕" : "⚠")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isError
                            ? Color(red: 0.92, green: 0.40, blue: 0.40)
                            : Color(red: 0.95, green: 0.72, blue: 0.22)
                        )

                    Text(message)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(isError
                            ? Color(red: 0.92, green: 0.40, blue: 0.40)
                            : Color(red: 0.95, green: 0.72, blue: 0.22)
                        )
                        .lineLimit(nil)
                }
            }
        }
    }
}

/// Opaque black background behind the window content.
///
/// This custom drawing keeps the panel look predictable from a
/// SwiftPM-launched executable.
private struct PanelBackground: View {
    var body: some View {
        Color.black
    }
}

/// Makes the dashboard's scroll bar match the black panel.
///
/// SwiftUI draws the standard macOS scroll bar, which follows the system's
/// light or dark setting and looks out of place on a black window. This finds
/// the scroll view that contains it and gives it the dark appearance with a
/// light knob. It changes only how the bar looks, not how scrolling works.
private struct DarkScrollerStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        // The view is not yet inside the scroll view when it is first created,
        // so apply the style on the next pass through the run loop.
        Task { @MainActor [weak view] in
            guard let scrollView = view?.enclosingScrollView else {
                return
            }

            scrollView.appearance = NSAppearance(named: .darkAqua)
            scrollView.scrollerKnobStyle = .light
        }
    }
}
