import SwiftUI

/// Shared health state used by the UI and monitoring logic.
///
/// Values are assigned by `SeverityEngine` for live remote metrics.
enum Severity: String {
    /// All enabled checks passed.
    case ok = "OK"

    /// One or more checks are degraded, but the server is still reachable.
    case warning = "WARNING"

    /// A critical check failed or the server is unreachable.
    case error = "ERROR"

    /// The app does not yet have enough reliable data to decide.
    case unknown = "UNKNOWN"

    /// Compact label for the narrow window UI.
    var shortLabel: String {
        switch self {
        case .ok:
            "OK"
        case .warning:
            "WARN"
        case .error:
            "ERR"
        case .unknown:
            "UNK"
        }
    }

    /// Display color used by the compact window UI.
    ///
    /// These colors are intentionally muted so the widget stays readable without
    /// becoming a noisy dashboard.
    var color: Color {
        switch self {
        case .ok:
            Color(red: 0.32, green: 0.78, blue: 0.65)
        case .warning:
            Color(red: 0.92, green: 0.66, blue: 0.26)
        case .error:
            Color(red: 0.95, green: 0.32, blue: 0.32)
        case .unknown:
            Color(red: 0.55, green: 0.58, blue: 0.62)
        }
    }
}
