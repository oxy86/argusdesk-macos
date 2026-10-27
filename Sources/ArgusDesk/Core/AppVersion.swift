import Foundation

/// Single source for the ArgusDesk app version displayed by the UI and used by
/// release notes.
enum AppVersion {
    /// Human-readable semantic version for this local build.
    static let current = "0.9"

    /// Compact UI label.
    static let displayName = "v\(current)"
}
